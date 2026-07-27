defmodule Sanctum.Games.Aspect do
  @moduledoc """
  A player-card aspect, as a data-driven lookup row rather than a hard-coded
  enum, so homebrew projects can define their own aspects (e.g. the community's
  fifth aspect "Determination").

  Identity is a stable string `key` — the official aspects seed with keys
  identical to the values the old `CardAspect`/`DeckAspect` enums used
  (`"aggression"`, `"justice"`, `"leadership"`, `"protection"`, `"pool"`), so
  `CardSide.aspect` and `Deck.aspects` keep storing those exact strings and only
  the *type* changed (enum → string). Custom aspects (a later phase) get
  synthetic keys outside that space and hang off a `homebrew_project`.

  The canonical official definitions live in code (`official/0`) — that is the
  single source of truth the seed inserts and the search registries read their
  value lists from. The DB rows exist for joins, admin visibility, and the
  custom aspects to come.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  # Colors mirror the --color-aspect-* tokens in assets/css/app.css.
  @official [
    %{key: "aggression", label: "Aggression", color: "#b12020", sort_order: 1},
    %{key: "justice", label: "Justice", color: "#dbcb36", sort_order: 2},
    %{key: "leadership", label: "Leadership", color: "#2ea7b8", sort_order: 3},
    %{key: "protection", label: "Protection", color: "#46991b", sort_order: 4},
    %{key: "pool", label: "'Pool", color: "#d074ac", sort_order: 5}
  ]

  @doc "Canonical official aspect definitions (source of truth for the seed)."
  def official, do: @official

  @doc "The five official aspect keys, in printed order."
  def official_keys, do: Enum.map(@official, & &1.key)

  @doc """
  Keys a deck can be built around. All five official aspects are deck-selectable
  (Deadpool's 'Pool included); custom aspects carry their own `deck_selectable`.
  """
  def deck_selectable_keys, do: official_keys()

  postgres do
    table "aspects"
    repo Sanctum.Repo

    references do
      # A deleted homebrew project takes its custom aspects with it.
      reference :homebrew_project, on_delete: :delete, index?: true
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:key, :label, :color, :sort_order, :origin, :deck_selectable, :homebrew_project_id]
    end

    update :update do
      primary? true
      accept [:label, :color, :sort_order, :deck_selectable]
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Phase 1: only official rows exist, so reads are open. When custom
    # (project-scoped) aspects land, this gains published-or-own filter checks
    # mirroring Card's read policy.
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:admin, true)
    end
  end

  attributes do
    # Stable string identity — official keys match the old enum values.
    attribute :key, :string, primary_key?: true, allow_nil?: false, public?: true, writable?: true

    attribute :label, :string, public?: true, allow_nil?: false
    # Hex, source of truth for theming (custom aspects render inline from this).
    attribute :color, :string, public?: true, allow_nil?: false
    attribute :sort_order, :integer, public?: true, allow_nil?: false, default: 100

    attribute :origin, Sanctum.Games.CardOrigin,
      public?: true,
      allow_nil?: false,
      default: :official

    # Whether a deck can be built around this aspect.
    attribute :deck_selectable, :boolean, public?: true, allow_nil?: false, default: true

    timestamps()
  end

  relationships do
    # Set for custom (project-scoped) aspects only; nil for the official five.
    belongs_to :homebrew_project, Sanctum.Homebrew.HomebrewProject do
      public? true
      allow_nil? true
    end
  end
end
