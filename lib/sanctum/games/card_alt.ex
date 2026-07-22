defmodule Sanctum.Games.CardAlt do
  @moduledoc """
  Alternate art/printings of a canonical `Card`, in two origins:

    * `:official` — MarvelCDB reprints a card under a new code with
      `duplicate_of_code` pointing back to the original. Rather than create a
      second `Card` (which would pollute the pool and deck resolution), each
      reprint side is stored as a thin `CardAlt` pointing at the canonical
      card. Deck slots that reference a reprint code resolve to the canonical
      card via this table.

    * `:custom` — user-declared homebrew alt art (`Sanctum.Homebrew`): a
      custom card CONVERTED into alternate art for an official card. Carries
      the creator/project FKs and an artist credit; its `code` is the source
      card's synthetic `custom-<uuid>` code, outside MarvelCDB's numeric
      space, so deck-slot resolution can never match it. Visibility follows
      the project (published → everyone, else creator-only).
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "card_alts"
    repo Sanctum.Repo

    custom_indexes do
      index [:pack_id]
    end

    references do
      # A deleted homebrew project (or user) takes its custom alts with it,
      # mirroring cards. Indexed — the read policy joins through the project
      # FK on every alt load.
      reference :homebrew_project, on_delete: :delete, index?: true
      reference :creator, on_delete: :delete, index?: true
    end

    check_constraints do
      # An official alt can never carry homebrew provenance; a custom alt can
      # never be orphaned. Mirrors cards_origin_project_consistency.
      check_constraint :origin,
        name: "card_alts_origin_consistency",
        check:
          "(origin = 'official') = (homebrew_project_id IS NULL) AND " <>
            "(origin = 'official') = (creator_id IS NULL)"
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:*]
      upsert? true
      upsert_identity :unique_alt_code
    end

    update :update do
      primary? true
      accept [:*]
    end

    destroy :destroy do
      primary? true
    end

    # Deck-import/writeup code resolution only — pinned to :official so a
    # custom alt can never resolve a slot code, even through the
    # authorize?: false callers in Sanctum.MarvelCdb where read policies
    # don't apply. (Custom codes are custom-<uuid>, outside the numeric
    # space, so a match is unconstructible anyway — this makes the invariant
    # explicit rather than emergent.)
    read :by_code do
      argument :code, :string, allow_nil?: false
      filter expr(code == ^arg(:code) and origin == :official)
    end

    read :by_codes do
      argument :codes, {:array, :string}, allow_nil?: false
      filter expr(code in ^arg(:codes) and origin == :official)
    end

    # -- Homebrew (custom) alt art ------------------------------------------
    # User-scoped through policies — never the authorize?: false system-write
    # paths used by catalog sync.

    create :declare_custom do
      description "Converts one of the actor's single-sided custom cards into " <>
                    "alternate art for an official card; the card row is destroyed."

      accept []

      argument :source_card_id, :uuid, allow_nil?: false
      argument :target_card_id, :uuid, allow_nil?: false
      argument :side_identifier, :string, default: "a"
      argument :artist, :string

      change Sanctum.Games.Changes.DeclareAltArt
    end

    destroy :revert_custom do
      description "Converts a custom alt back into a plain image-only custom " <>
                    "card in the same project."

      require_atomic? false

      change Sanctum.Games.Changes.RevertAltArt
    end

    destroy :destroy_custom do
      description "Deletes a custom alt outright."
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Filter policy — custom alts follow their project's visibility; official
    # alts are visible to everyone. Checks stay separate on purpose: an expr
    # referencing ^actor(:id) collapses to false wholesale under a nil actor
    # (see Card's read policy) — folding these into one OR would hide official
    # alts from anonymous card pages.
    policy action_type(:read) do
      authorize_if expr(origin == :official)
      authorize_if expr(homebrew_project.visibility == :published)
      authorize_if expr(creator_id == ^actor(:id))
    end

    # Create-time check resolving the :source_card_id ARGUMENT by hand —
    # filter checks can't see the source card on a create, and attributes set
    # in before_action hooks are invisible to policies (authorization runs
    # first).
    policy action(:declare_custom) do
      authorize_if Sanctum.Homebrew.Checks.ActorOwnsSourceCard
    end

    # Filter checks: someone else's custom alt (or any official alt) is
    # simply not found through these actions.
    policy action([:revert_custom, :destroy_custom]) do
      authorize_if expr(origin == :custom and creator_id == ^actor(:id))
    end

    # Official catalog mutations stay admin-only; system writes (sync) go
    # through Sanctum.MarvelCdb with authorize?: false. Enumerated by action
    # (not action_type) so this never also applies to the custom actions
    # above — every applicable policy must pass.
    policy action([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:admin, true)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    # The printing's own code: a MarvelCDB side code (e.g. "16021a") for
    # official reprints, the source card's custom-<uuid> code for custom alts.
    attribute :code, :string, public?: true, allow_nil?: false
    attribute :base_code, :string, public?: true, allow_nil?: false

    # For custom alts: the TARGET side the art depicts.
    attribute :side_identifier, :string, public?: true

    attribute :pack, :string, public?: true
    attribute :set, :string, public?: true
    attribute :image_url, :string, public?: true

    # Official catalog reprint vs. user-declared homebrew alt art.
    attribute :origin, Sanctum.Games.CardOrigin,
      public?: true,
      allow_nil?: false,
      default: :official

    # Artist credit for custom alts (IP posture: attribution).
    attribute :artist, :string, public?: true

    timestamps()
  end

  relationships do
    # The canonical card this is an alternate printing of / alt art for.
    belongs_to :card, Sanctum.Games.Card do
      public? true
      allow_nil? false
    end

    # Catalog FK mirroring Card.pack_ref (the `pack` string above is the
    # legacy MarvelCDB code). Lets collection ownership count reprints:
    # owning the pack a reprint shipped in owns the canonical card. Always
    # nil for custom alts — they contribute nothing to ownership.
    belongs_to :pack_ref, Sanctum.Catalog.Pack do
      public? true
      allow_nil? true
      source_attribute :pack_id
    end

    # Set for :custom origin only (see the origin check constraint).
    belongs_to :creator, Sanctum.Accounts.User do
      public? true
      allow_nil? true
    end

    belongs_to :homebrew_project, Sanctum.Homebrew.HomebrewProject do
      public? true
      allow_nil? true
    end
  end

  identities do
    identity :unique_alt_code, [:code]
  end
end
