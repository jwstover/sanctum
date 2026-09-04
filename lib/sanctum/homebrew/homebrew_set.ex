defmodule Sanctum.Homebrew.HomebrewSet do
  @moduledoc """
  A publishable homebrew *set* — the public artifact of the custom-content
  model ("Daredevil hero pack", "Kingpin scenario"). Sets live inside a
  `HomebrewProject`, which is the creator's private workspace; the set
  carries its own visibility/maturity so it can be published independently.

  `creator_id` is DENORMALIZED from the project and stamped server-side on
  create (`Changes.SetCreatorFromProject`); it is never user input. Content
  read policies (Card/CardSide/CardAlt) will later filter on the set's
  creator on every card read — routing through the project would add a join.

  `set_kind` is a nullable uuid FK to `SetKind` (not `key`: keys are only
  unique per project). Unclassified (nil) is a legal state; a classified set
  points at an official kind or a custom kind from its own project
  (`Validations.SetKindInSameProject`).

  `parent_set` nests sets within one project (a hero pack owning its nemesis
  set); a parent's destruction cascades to its children.

  Sets start `:private`; visibility is walked through `:set_visibility` so
  the publish flow (attestation gate, slug, review) can hang off that action.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Homebrew,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

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
      # not accepted either (generation is a later task).
      accept [
        :homebrew_project_id,
        :name,
        :description,
        :banner_url,
        :set_kind_id,
        :maturity,
        :tags,
        :parent_set_id,
        :attestation
      ]

      change Sanctum.Homebrew.Changes.SetCreatorFromProject

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
    end

    update :update do
      primary? true
      # ParentSetInSameProject / SetKindInSameProject read other rows — not
      # atomic-capable.
      require_atomic? false

      # No homebrew_project_id (a set never moves projects), no creator_id,
      # no visibility (that is :set_visibility's job), no slug.
      accept [
        :name,
        :description,
        :banner_url,
        :set_kind_id,
        :maturity,
        :tags,
        :parent_set_id,
        :attestation
      ]

      validate Sanctum.Homebrew.Validations.ParentSetInSameProject,
        where: [changing(:parent_set_id)],
        before_action?: true

      validate Sanctum.Homebrew.Validations.SetKindInSameProject,
        where: [changing(:set_kind_id)],
        before_action?: true
    end

    # Visibility transitions are their own action so the publish flow
    # (attestation gate, slug generation, review) can add changes/validations
    # here without touching general editing. Mirrors HomebrewProject.
    update :set_visibility do
      accept [:visibility]
    end

    destroy :destroy do
      primary? true
    end

    read :for_creator do
      filter expr(creator_id == ^actor(:id))
    end

    read :by_project do
      argument :homebrew_project_id, :uuid, allow_nil?: false
      filter expr(homebrew_project_id == ^arg(:homebrew_project_id))
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
    policy action_type(:read) do
      authorize_if expr(visibility == :published)
      authorize_if expr(creator_id == ^actor(:id))
    end

    # Create: the actor must own the target project. Filter checks can't see
    # the project on a create, so the SimpleCheck resolves the accepted
    # homebrew_project_id by hand (nil actor → false → Forbidden).
    policy action_type(:create) do
      authorize_if Sanctum.Homebrew.Checks.ActorOwnsProject
    end

    # Covers :update, :set_visibility and :destroy. Filter check on the
    # denormalized column — no join through the project — so someone else's
    # set is simply not reachable through these actions.
    policy action_type([:update, :destroy]) do
      authorize_if expr(creator_id == ^actor(:id))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false

    # Nullable placeholder; slug generation (and its uniqueness identity)
    # land with the publish flow. Not accepted by any action yet.
    attribute :slug, :string, public?: true

    # Markdown, rendered on the set page.
    attribute :description, :string, public?: true
    attribute :banner_url, :string, public?: true

    attribute :visibility, Sanctum.Homebrew.Visibility,
      public?: true,
      allow_nil?: false,
      default: :private

    attribute :maturity, Sanctum.Homebrew.Maturity,
      public?: true,
      allow_nil?: false,
      default: :draft

    attribute :tags, {:array, :string}, public?: true, default: []

    # Publish-time claim: "my own work, or shared with the creator's
    # permission". Accepted on create/update but NOT required true here —
    # the publish flow (set_visibility → :published) will gate on it later.
    attribute :attestation, :boolean, public?: true, allow_nil?: false, default: false

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

    # has_many :cards / :card_alts and the card_count / alt_count aggregates
    # arrive with the FK re-point (Card/CardAlt.homebrew_set_id, task #3).
  end
end
