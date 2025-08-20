defmodule Sanctum.Games.Card do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "cards"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [:*]

      upsert? true
      upsert_identity :unique_marvelcdb_code
    end

    read :by_type do
      argument :card_type, :atom, allow_nil?: false
      filter expr(type == ^arg(:card_type))
    end

    read :by_aspect do
      argument :aspect, :atom, allow_nil?: false
      filter expr(aspect == ^arg(:aspect))
    end

    read :by_set do
      argument :set, :string, allow_nil?: false
      filter expr(set == ^arg(:set))
    end

    read :search do
      argument :query, :string, allow_nil?: false
      filter expr(contains(name, ^arg(:query)) or contains(text, ^arg(:query)))
    end

    read :by_code do
      argument :code, :string, allow_nil?: false
      filter expr(code == ^arg(:code))
    end

    read :by_pack do
      argument :pack, :string, allow_nil?: false
      filter expr(pack == ^arg(:pack))
    end

    update :update do
      primary? true

      accept [:*]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :subname, :string, public?: true
    attribute :traits, {:array, :string}, public?: true, default: []
    attribute :type, Sanctum.Games.CardType, public?: true, allow_nil?: true
    attribute :aspect, Sanctum.Games.CardAspect, public?: true

    attribute :text, :string, public?: true

    attribute :attack, :integer, public?: true
    attribute :attack_cost, :integer, public?: true

    attribute :thwart, :integer, public?: true
    attribute :thwart_cost, :integer, public?: true

    attribute :defense, :integer, public?: true
    attribute :defense_cost, :integer, public?: true

    attribute :health, :integer, public?: true

    attribute :cost, :integer, public?: true

    attribute :deck_limit, :integer, public?: true
    attribute :unique, :boolean, public?: true, default: false
    attribute :permanent, :boolean, public?: true, default: false

    attribute :acceleration_icon, :boolean, public?: true, default: false
    attribute :amplify_icon, :boolean, public?: true, default: false
    attribute :crisis_icon, :boolean, public?: true, default: false
    attribute :hazard_icon, :boolean, public?: true, default: false

    # ── Resource Fields ───────────────────────────────────────────────────

    attribute :resource_energy_count, :integer, public?: true
    attribute :resource_physical_count, :integer, public?: true
    attribute :resource_mental_count, :integer, public?: true
    attribute :resource_wild_count, :integer, public?: true

    # ── Hero Fields ───────────────────────────────────────────────────────

    attribute :hand_size, :integer, public?: true

    attribute :recover, :integer, public?: true

    # ── Villian Fields ────────────────────────────────────────────────────

    attribute :health_per_hero, :boolean, public?: true, default: false
    attribute :stage, :integer, public?: true

    # ── Scheme Fields ─────────────────────────────────────────────────────

    attribute :base_threat, :integer, public?: true
    attribute :escalation_threat, :integer, public?: true
    attribute :max_threat, :integer, public?: true

    # ── Encounter Fields ──────────────────────────────────────────────────

    attribute :boost, :integer, public?: true
    attribute :boost_star, :boolean, public?: true, default: false

    # ── Categorization Fields ─────────────────────────────────────────────

    attribute :set, :string, public?: true
    attribute :pack, :string, public?: true
    attribute :code, :string, public?: true, allow_nil?: false
    attribute :image_url, :string, public?: true, allow_nil?: true

    timestamps()
  end

  identities do
    identity :unique_marvelcdb_code, [:code]
  end
end
