defmodule Sanctum.Games.CardSide do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "card_sides"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:*]
    end

    update :update do
      primary? true
      accept [:*]
    end

    read :primary_sides do
      filter expr(is_primary_side == true)
    end

    read :by_code do
      argument :code, :string, allow_nil?: false
      filter expr(code == ^arg(:code))
    end

    read :by_card_and_side do
      argument :card_id, :uuid, allow_nil?: false
      argument :side_identifier, :string, allow_nil?: false
      filter expr(card_id == ^arg(:card_id) and side_identifier == ^arg(:side_identifier))
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    # Side identification
    attribute :side_identifier, :string, public?: true, allow_nil?: false
    attribute :is_primary_side, :boolean, public?: true, default: false
    attribute :code, :string, public?: true, allow_nil?: false

    # Core card content
    attribute :name, :string, public?: true, allow_nil?: false
    attribute :subname, :string, public?: true
    attribute :traits, {:array, :string}, public?: true, default: []
    attribute :type, Sanctum.Games.CardType, public?: true, allow_nil?: true
    attribute :aspect, Sanctum.Games.CardAspect, public?: true

    attribute :text, :string, public?: true

    # Combat stats
    attribute :attack, :integer, public?: true
    attribute :attack_cost, :integer, public?: true

    attribute :thwart, :integer, public?: true
    attribute :thwart_cost, :integer, public?: true

    attribute :defense, :integer, public?: true
    attribute :defense_cost, :integer, public?: true

    attribute :health, :integer, public?: true

    attribute :cost, :integer, public?: true

    # Icons
    attribute :acceleration_icon, :boolean, public?: true, default: false
    attribute :amplify_icon, :boolean, public?: true, default: false
    attribute :crisis_icon, :boolean, public?: true, default: false
    attribute :hazard_icon, :boolean, public?: true, default: false

    # Resource Fields
    attribute :resource_energy_count, :integer, public?: true
    attribute :resource_physical_count, :integer, public?: true
    attribute :resource_mental_count, :integer, public?: true
    attribute :resource_wild_count, :integer, public?: true

    # Hero Fields
    attribute :hand_size, :integer, public?: true
    attribute :recover, :integer, public?: true

    # Villain Fields
    attribute :health_per_hero, :boolean, public?: true, default: false
    attribute :stage, :integer, public?: true
    attribute :scheme, :integer, public?: true

    # Scheme Fields
    attribute :base_threat, :integer, public?: true
    attribute :escalation_threat, :integer, public?: true
    attribute :max_threat, :integer, public?: true

    # Encounter Fields
    attribute :boost, :integer, public?: true
    attribute :boost_star, :boolean, public?: true, default: false

    # Image
    attribute :image_url, :string, public?: true, allow_nil?: true

    timestamps()
  end

  relationships do
    belongs_to :card, Sanctum.Games.Card do
      public? true
      allow_nil? false
    end
  end

  identities do
    identity :unique_card_side, [:card_id, :side_identifier]
    identity :unique_code, [:code]
  end
end
