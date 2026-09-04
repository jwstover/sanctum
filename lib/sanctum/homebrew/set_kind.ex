defmodule Sanctum.Homebrew.SetKind do
  @moduledoc """
  The *kind* of a card set — hero, scenario, modular, alt art, … — as a
  data-driven lookup row rather than a hard-coded enum, so homebrew projects
  can define their own kinds (a "hazard deck", a "nemesis pack") without a
  code change.

  Two origins share the table:

    * `:official` — the canonical kinds shipped in code (`official/0`), seeded
      by `Sanctum.Release.seed_set_kinds/0`. No `homebrew_project`; visible to
      everyone, including anonymous readers; admin-only mutations.

    * `:custom` — project-scoped kinds minted by a project's creator through
      `Sanctum.Homebrew.create_set_kind/2`. Visibility follows the project
      (published → everyone, else creator-only).

  `key` is a stable machine identifier. It is unique across all official kinds
  and unique *within* a project for custom kinds — two projects can each mint
  a `"hazard_deck"` without colliding, and a custom key may shadow an official
  one. Nothing validates a key against a fixed list of kinds; the only
  constraint is the light structural format check.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Homebrew,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @official [
    %{key: "hero", label: "Hero", sort_order: 1},
    %{key: "scenario", label: "Scenario", sort_order: 2},
    %{key: "modular", label: "Modular", sort_order: 3},
    %{key: "aspect", label: "Aspect", sort_order: 4},
    %{key: "player_cards", label: "Player Cards", sort_order: 5},
    %{key: "alt_art", label: "Alt Art", sort_order: 6},
    %{key: "campaign", label: "Campaign", sort_order: 7},
    %{key: "other", label: "Other", sort_order: 100}
  ]

  @key_format ~r/\A[a-z0-9][a-z0-9_-]*\z/

  @doc "Canonical official set-kind definitions (source of truth for the seed)."
  def official, do: @official

  @doc "The official set-kind keys, in display order."
  def official_keys, do: Enum.map(@official, & &1.key)

  postgres do
    table "set_kinds"
    repo Sanctum.Repo

    references do
      # A deleted homebrew project takes its custom kinds with it. Indexed —
      # the read policy joins through the project FK on every load.
      reference :homebrew_project, on_delete: :delete, index?: true
    end

    check_constraints do
      # An official kind never carries project provenance; a custom kind can
      # never be orphaned. Mirrors card_alts_origin_consistency.
      check_constraint :origin,
        name: "set_kinds_origin_consistency",
        check: "(origin = 'official') = (homebrew_project_id IS NULL)"
    end
  end

  actions do
    defaults [:read]

    # System/admin create — the seed and admin tooling. Custom kinds go
    # through :create_custom below so the origin is pinned server-side.
    create :create do
      primary? true
      accept [:key, :label, :sort_order, :origin, :homebrew_project_id]
    end

    create :create_custom do
      description "Mints a project-scoped custom set kind owned by the actor's project."

      accept [:key, :label, :sort_order, :homebrew_project_id]
      require_attributes [:homebrew_project_id]

      change set_attribute(:origin, :custom)
    end

    update :update do
      primary? true
      accept [:label, :sort_order]
    end

    destroy :destroy do
      primary? true
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Filter policy — custom kinds follow their project's visibility; official
    # kinds are visible to everyone. Checks stay separate on purpose: an expr
    # referencing ^actor(:id) collapses to false wholesale under a nil actor
    # (see CardAlt's read policy) — folding these into one OR would hide
    # official kinds from anonymous readers.
    policy action_type(:read) do
      authorize_if expr(origin == :official)
      authorize_if expr(homebrew_project.visibility == :published)
      authorize_if expr(homebrew_project.creator_id == ^actor(:id))
    end

    # Custom create: the actor must own the target project. The project id is
    # an accepted attribute, so the check can resolve it on the changeset.
    policy action(:create_custom) do
      authorize_if Sanctum.Homebrew.Checks.ActorOwnsProject
    end

    # Filter checks: someone else's custom kind (or any official kind) is
    # simply not reachable through these actions for a non-admin.
    policy action([:update, :destroy]) do
      authorize_if expr(origin == :custom and homebrew_project.creator_id == ^actor(:id))
    end

    # Official kinds are admin-only to mint; the seed runs with
    # authorize?: false. Enumerated by action (not action_type) so this never
    # also applies to :create_custom — every applicable policy must pass.
    policy action(:create) do
      authorize_if actor_attribute_equals(:admin, true)
    end
  end

  preparations do
    prepare build(sort: [sort_order: :asc, label: :asc])
  end

  validations do
    validate match(:key, @key_format) do
      on [:create]

      message "must be lowercase letters, digits, underscores or hyphens, starting with a letter or digit"
    end
  end

  attributes do
    uuid_v7_primary_key :id

    # Stable machine identifier: globally unique for official kinds, unique
    # per project for custom kinds (see the identity below).
    attribute :key, :string, public?: true, allow_nil?: false
    attribute :label, :string, public?: true, allow_nil?: false
    attribute :sort_order, :integer, public?: true, allow_nil?: false, default: 100

    attribute :origin, Sanctum.Games.CardOrigin,
      public?: true,
      allow_nil?: false,
      default: :official

    timestamps()
  end

  relationships do
    # Set for custom (project-scoped) kinds only; nil for official kinds.
    belongs_to :homebrew_project, Sanctum.Homebrew.HomebrewProject do
      public? true
      allow_nil? true
    end
  end

  identities do
    # nils_distinct?: false → Postgres NULLS NOT DISTINCT, so two official
    # rows (NULL project) with the same key collide, while the same key in two
    # different projects does not.
    identity :unique_key_per_project, [:key, :homebrew_project_id], nils_distinct?: false
  end
end
