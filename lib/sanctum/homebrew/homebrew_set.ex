defmodule Sanctum.Homebrew.HomebrewSet do
  @moduledoc """
  A publishable homebrew *set* — the public artifact of the custom-content
  model ("Daredevil hero pack", "Kingpin scenario"). Sets live inside a
  `HomebrewProject`, which is the creator's private workspace; the set
  carries its own visibility so it can be published independently.

  `creator_id` is DENORMALIZED from the project and stamped server-side on
  create (`Changes.SetCreatorFromProject`); it is never user input. Content
  read policies (Card/CardSide/CardAlt) will later filter on the set's
  creator on every card read — routing through the project would add a join.

  `set_kind` is a nullable uuid FK to `SetKind` (not `key`: keys are only
  unique per project). Unclassified (nil) is a legal state; a classified set
  points at an official kind or a custom kind from its own project
  (`Validations.SetKindInSameProject`).

  `parent_set` nests sets within one project (a hero pack owning its nemesis
  set, a campaign owning its scenarios) to any depth; a parent's destruction
  cascades to its children. Re-parenting goes through `:set_parent`, which
  guards against cycles; `:subtree` and `:ancestors` are the shared tree
  walks.

  Sets start `:private`; visibility is walked only through `:set_visibility`.
  An `:unlisted` set is reachable only through `:by_creator_slug` (its share
  link); the default read filter admits `:published` and the creator's own
  sets, never `:unlisted`, so unlisted sets stay out of every listing.
  Publishing there requires the creator to have claimed a username and, the
  first time, a publish attestation, which is recorded as
  `attestation`/`attested_at`. The general `:update` can write neither
  visibility nor the attestation.

  `slug` is unique per *creator* (`(creator_id, slug)` identity), not
  globally: the public URL is `/custom/@username/slug`, so two creators can
  both publish a `daredevil` and attribution lives in the URL. It is derived
  from the name on create (`Changes.GenerateSlug`, disambiguated only among
  the creator's own sets) and never follows a rename — `:regenerate_slug` is
  the explicit way to re-derive it. A username change breaks the creator's
  URLs by design (old links 404).
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Homebrew,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @https_url ~r/\Ahttps:\/\/\S+\z/

  postgres do
    table "homebrew_sets"
    repo Sanctum.Repo

    references do
      # A deleted project takes its sets with it. Indexed — :by_project filters on it.
      reference :homebrew_project, on_delete: :delete, index?: true
      # Denormalized owner; indexed because the read policy filters on it directly.
      reference :creator, on_delete: :delete, index?: true
      # Deleting a kind leaves the set unclassified rather than deleting content.
      reference :set_kind, on_delete: :nilify
      # Child sets die with their parent.
      reference :parent_set, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true

      # homebrew_project_id MUST be an accepted attribute: the ActorOwnsProject
      # policy resolves it off the changeset. creator_id is deliberately NOT
      # accepted — SetCreatorFromProject stamps it from the project. slug is
      # not accepted either: GenerateSlug derives it from the name.
      accept [
        :homebrew_project_id,
        :name,
        :description,
        :banner_url,
        :set_kind_id,
        :tags,
        :parent_set_id
      ]

      change Sanctum.Homebrew.Changes.SetCreatorFromProject
      # After SetCreatorFromProject: both are before_action hooks, run in
      # order, and the slug is disambiguated against the stamped creator.
      change Sanctum.Homebrew.Changes.GenerateSlug

      # Action-level (not a global `validations do`): a global `on [:update]`
      # validation would also attach to the atomic :set_visibility action and
      # trip VerifyActionsAtomic under --warnings-as-errors.
      #
      # before_action? so both run AFTER the create policy: they look up
      # arbitrary caller-supplied ids with authorize?: false, and an actor who
      # does not own the project must get Forbidden — not a same-project
      # Invalid that doubles as an existence oracle for private rows.
      validate Sanctum.Homebrew.Validations.ParentSetInSameProject,
        where: [changing(:parent_set_id)],
        before_action?: true

      validate Sanctum.Homebrew.Validations.SetKindInSameProject,
        where: [changing(:set_kind_id)],
        before_action?: true

      validate match(:banner_url, @https_url), message: "must be an https:// URL"
    end

    update :update do
      primary? true
      # ParentSetInSameProject / SetKindInSameProject read other rows — not
      # atomic-capable.
      require_atomic? false

      # No homebrew_project_id (a set never moves projects), no creator_id,
      # no visibility or publish attestation (both are :set_visibility's
      # job), no slug, and no
      # parent_set_id (re-parenting is :set_parent's job — the one place the
      # cycle guard lives).
      accept [
        :name,
        :description,
        :banner_url,
        :set_kind_id,
        :tags
      ]

      validate Sanctum.Homebrew.Validations.SetKindInSameProject,
        where: [changing(:set_kind_id)],
        before_action?: true

      validate match(:banner_url, @https_url), message: "must be an https:// URL"

      # Free kind text from the set page's open combobox: resolves to an
      # existing kind or mints a project-scoped one (blank → unclassified).
      # An alternative to passing set_kind_id directly.
      argument :kind, :string, allow_nil?: true
      change Sanctum.Homebrew.Changes.ResolveSetKind
    end

    # The visibility ladder (:private → :unlisted → :published, and back
    # down to unpublish), kept apart from general editing so the publish gates
    # live in one place. Moving to :published needs a claimed username on the
    # creator every time, and the first time also needs the publish
    # attestation (`attest: true`), which is stamped with a timestamp.
    update :set_visibility do
      accept [:visibility]
      # GenerateSlug, the username check and the attestation all read state.
      require_atomic? false

      argument :attest, :boolean, default: false

      # before_action? so these run after the update policy.
      validate Sanctum.Homebrew.Validations.CreatorHasUsername, before_action?: true
      change Sanctum.Homebrew.Changes.RecordPublishAttestation

      # Sets created before slugs existed get one on their way out; an
      # existing slug (and so a shared URL) is never touched here.
      change {Sanctum.Homebrew.Changes.GenerateSlug, only_if_missing?: true}
    end

    # Re-derive the slug from the current name — the one way a rename moves
    # the public URL. A slug that already matches the name is kept.
    update :regenerate_slug do
      accept []
      require_atomic? false
      change Sanctum.Homebrew.Changes.GenerateSlug
    end

    # Nest the set under another set of its project, or clear the link
    # (nil → top level). Depth is unbounded; the set's whole subtree comes
    # along because only this row's parent_set_id changes.
    update :set_parent do
      accept [:parent_set_id]
      # Both validations read other rows (and NoParentCycle locks the project).
      require_atomic? false

      # before_action? so they run after the update policy, inside the
      # action's transaction (see ParentSetInSameProject's moduledoc).
      validate Sanctum.Homebrew.Validations.ParentSetInSameProject, before_action?: true
      validate Sanctum.Homebrew.Validations.NoParentCycle, before_action?: true
    end

    destroy :destroy do
      primary? true
    end

    read :for_creator do
      filter expr(creator_id == ^actor(:id))
    end

    # The public URL lookup: creator handle + slug → at most one set (the
    # (creator_id, slug) identity plus unique usernames). This is the ONE read
    # path that resolves :unlisted sets for anyone — knowing the link is the
    # access (see the action's own policy below). The default read filter
    # never admits :unlisted, so unlisted sets stay out of every listing. A
    # private set resolves only for its creator; a renamed or unknown
    # username simply finds nothing.
    read :by_creator_slug do
      get? true
      argument :username, :ci_string, allow_nil?: false
      argument :slug, :string, allow_nil?: false
      filter expr(creator.username == ^arg(:username) and slug == ^arg(:slug))
    end

    # The public set directory (/custom). Pins visibility to :published
    # explicitly — the read policy would also admit the actor's own private
    # sets (and admins bypass it entirely), and a directory must never list
    # those. Facets are optional and combine (Preparations.DirectoryFilters).
    # Newest first by first-publish time (attested_at).
    read :directory do
      argument :kind, :string, allow_nil?: true
      argument :creator, :ci_string, allow_nil?: true
      argument :tag, :string, allow_nil?: true

      argument :recency, :string,
        allow_nil?: true,
        constraints: [match: ~r/\A(week|month|year)\z/]

      filter expr(visibility == :published and not is_nil(slug))

      prepare Sanctum.Homebrew.Preparations.DirectoryFilters

      prepare build(
                load: [:set_kind, :card_count, creator: [:username]],
                sort: [attested_at: :desc_nils_last, inserted_at: :desc, id: :desc]
              )

      pagination offset?: true, default_limit: 48, countable: true, required?: false
    end

    # A set's published descendants at any depth (the set itself excluded) —
    # the grouped sections of its public page. Pinned to :published so the
    # public page never shows a private or unlisted child, whoever is
    # looking (admins bypass the read policy).
    read :published_descendants do
      argument :set_id, :uuid, allow_nil?: false

      filter expr(
               visibility == :published and id != ^arg(:set_id) and
                 fragment(
                   "? IN (WITH RECURSIVE subtree(id) AS (SELECT id FROM homebrew_sets WHERE id = ? UNION SELECT s.id FROM homebrew_sets s JOIN subtree ON s.parent_set_id = subtree.id) SELECT id FROM subtree)",
                   id,
                   type(^arg(:set_id), :uuid)
                 )
             )
    end

    # Creators and tags that occur on published sets — the directory's
    # facet options.
    action :directory_facets, :map do
      constraints fields: [
                    creators: [type: {:array, :string}, allow_nil?: false],
                    tags: [type: {:array, :string}, allow_nil?: false]
                  ]

      run Sanctum.Homebrew.Actions.DirectoryFacets
    end

    read :by_project do
      argument :homebrew_project_id, :uuid, allow_nil?: false
      filter expr(homebrew_project_id == ^arg(:homebrew_project_id))
    end

    # The set and every descendant at any depth — the one shared tree walk
    # (deletion blast radius, cycle checks, subtree moves). A recursive CTE
    # over parent_set_id, so depth costs one query, not one per level. Read
    # policies still apply on top.
    read :subtree do
      argument :set_id, :uuid, allow_nil?: false

      filter expr(
               fragment(
                 "? IN (WITH RECURSIVE subtree(id) AS (SELECT id FROM homebrew_sets WHERE id = ? UNION SELECT s.id FROM homebrew_sets s JOIN subtree ON s.parent_set_id = subtree.id) SELECT id FROM subtree)",
                 id,
                 type(^arg(:set_id), :uuid)
               )
             )
    end

    # The set's ancestors (parent, grandparent, ... root), excluding the set
    # itself — the upward counterpart of :subtree. Rows come back unordered;
    # rebuild the chain by following parent_set_id (see ancestor_chain/2 in
    # HomebrewLive.SetShow). Read policies still apply on top.
    read :ancestors do
      argument :set_id, :uuid, allow_nil?: false

      filter expr(
               fragment(
                 "? IN (WITH RECURSIVE ancestors(id, parent_set_id) AS (SELECT id, parent_set_id FROM homebrew_sets WHERE id = ? UNION SELECT s.id, s.parent_set_id FROM homebrew_sets s JOIN ancestors ON s.id = ancestors.parent_set_id) SELECT id FROM ancestors) AND ? != ?",
                 id,
                 type(^arg(:set_id), :uuid),
                 id,
                 type(^arg(:set_id), :uuid)
               )
             )
    end

    # What destroying a set takes with it: its whole subtree (the DB cascade
    # on parent_set_id and the content FKs). Counted before the confirmation
    # dialog opens. Published sets are named because a lost public link is
    # the regret nobody can see from the parent. deck_count is the decks
    # (anyone's) holding one of the subtree's cards: deck slots don't
    # cascade, so those block the destroy.
    action :deletion_impact, :map do
      constraints fields: [
                    descendant_set_count: [type: :integer, allow_nil?: false],
                    card_count: [type: :integer, allow_nil?: false],
                    alt_count: [type: :integer, allow_nil?: false],
                    published_sets: [type: {:array, :string}, allow_nil?: false],
                    deck_count: [type: :integer, allow_nil?: false]
                  ]

      argument :set_id, :uuid, allow_nil?: false
      run Sanctum.Homebrew.Actions.DeletionImpact
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Filter checks: non-matching rows are excluded from every read, so a
    # private/unlisted set is invisible — not "forbidden" — to everyone but
    # its creator (Ash.get → NotFound, wrapped in Ash.Error.Invalid).
    # Separate checks on purpose: an expr referencing ^actor(:id) collapses to
    # false wholesale under a nil actor, so folding these into one OR
    # (`visibility == :published or creator_id == ^actor(:id)`) would hide
    # published sets from anonymous reads. As at HomebrewProject/SetKind/CardAlt.
    #
    # :by_creator_slug is waved through here and filtered by its own policy
    # below (every applicable policy must pass, so admitting :unlisted can't
    # live in a second policy alone). Do NOT add :unlisted to this filter:
    # it would leak unlisted sets into every listing.
    policy action_type(:read) do
      authorize_if action(:by_creator_slug)
      authorize_if expr(visibility == :published)
      authorize_if expr(creator_id == ^actor(:id))
    end

    # The share-link path: anyone holding creator + slug sees a published or
    # unlisted set; a private one stays creator-only. Separate checks for the
    # same nil-actor reason as above.
    policy action(:by_creator_slug) do
      authorize_if expr(visibility in [:published, :unlisted])
      authorize_if expr(creator_id == ^actor(:id))
    end

    # Create: the actor must own the target project. Filter checks can't see
    # the project on a create, so the SimpleCheck resolves the accepted
    # homebrew_project_id by hand (nil actor → false → Forbidden).
    policy action_type(:create) do
      authorize_if Sanctum.Homebrew.Checks.ActorOwnsProject
    end

    # Covers :update, :set_visibility, :regenerate_slug and :destroy. Filter check on the
    # denormalized column — no join through the project — so someone else's
    # set is simply not reachable through these actions.
    policy action_type([:update, :destroy]) do
      authorize_if expr(creator_id == ^actor(:id))
    end

    # Public: it reads through :directory, which only ever sees published sets.
    policy action(:directory_facets) do
      authorize_if always()
    end

    # Only whoever may destroy the set sees its blast radius.
    policy action(:deletion_impact) do
      authorize_if Sanctum.Homebrew.Checks.ActorOwnsSetArgument
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false

    # Creator-scoped URL slug (see moduledoc). Written only by GenerateSlug;
    # nullable because sets predating slugs get one when published.
    attribute :slug, :string, public?: true

    # Markdown, rendered on the set page.
    attribute :description, :string, public?: true
    attribute :banner_url, :string, public?: true

    attribute :visibility, Sanctum.Homebrew.Visibility,
      public?: true,
      allow_nil?: false,
      default: :private

    attribute :tags, {:array, :string}, public?: true, default: []

    # Publish-time claim: "I'm allowed to distribute this, publicly, under my
    # name." Written only by :set_visibility (RecordPublishAttestation) on the
    # first publish, together with when it was made.
    attribute :attestation, :boolean, public?: true, allow_nil?: false, default: false
    attribute :attested_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :homebrew_project, Sanctum.Homebrew.HomebrewProject do
      public? true
      allow_nil? false
    end

    # Denormalized from homebrew_project.creator (see moduledoc).
    # attribute_writable? false keeps creator_id out of every accept list;
    # SetCreatorFromProject writes it with force_change_attribute.
    belongs_to :creator, Sanctum.Accounts.User do
      public? true
      allow_nil? false
      attribute_writable? false
    end

    belongs_to :set_kind, Sanctum.Homebrew.SetKind do
      public? true
      allow_nil? true
    end

    belongs_to :parent_set, __MODULE__ do
      public? true
      allow_nil? true
    end

    has_many :child_sets, __MODULE__ do
      destination_attribute :parent_set_id
      public? true
    end

    has_many :cards, Sanctum.Games.Card do
      destination_attribute :homebrew_set_id
    end

    has_many :card_alts, Sanctum.Games.CardAlt do
      destination_attribute :homebrew_set_id
    end

    has_many :aspects, Sanctum.Games.Aspect do
      destination_attribute :homebrew_set_id
    end
  end

  aggregates do
    count :card_count, :cards
    count :alt_count, :card_alts
  end

  identities do
    # Slugs are unique per creator, not globally. Postgres treats NULLs as
    # distinct, so legacy slug-less sets don't collide.
    identity :unique_creator_slug, [:creator_id, :slug]
  end
end
