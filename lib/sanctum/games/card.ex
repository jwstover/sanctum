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

      accept [
        :name,
        :card_type,
        :cost,
        :text,
        :flavor_text,
        :set_code,
        :card_number,
        :quantity,
        :unique,
        :aspect,
        :attack,
        :thwart,
        :defense,
        :hit_points,
        :scheme,
        :recovery,
        :resource_type,
        :resource_count,
        :traits,
        :keywords,
        :stage,
        :boost_icons,
        :hand_size,
        :base_threat,
        :escalation_threat,
        :acceleration_icon,
        :consequential_damage,
        # MarvelCDB fields
        :code,
        :pack_code,
        :pack_name,
        :real_name,
        :subname,
        :type_code,
        :type_name,
        :faction_code,
        :faction_name,
        :card_set_code,
        :card_set_name,
        :card_set_type_name_code,
        :position,
        :set_position,
        :linked_to_code,
        :linked_to_name,
        :deck_limit,
        :resource_energy,
        :resource_physical,
        :resource_mental,
        :resource_wild,
        :real_text,
        :boost,
        :cost_per_hero,
        :health_per_hero,
        :thwart_cost,
        :attack_cost,
        :defense_cost,
        :recover_cost,
        :attack_star,
        :thwart_star,
        :defense_star,
        :health_star,
        :recover_star,
        :scheme_star,
        :boost_star,
        :threat_star,
        :escalation_threat_star,
        :threat,
        :threat_fixed,
        :base_threat_fixed,
        :escalation_threat_fixed,
        :hidden,
        :permanent,
        :double_sided,
        :octgn_id,
        :url,
        :imagesrc,
        :illustrator,
        :errata,
        :spoiler,
        :meta,
        :back_text,
        :back_flavor,
        :back_name,
        :backimagesrc
      ]
    end

    read :by_type do
      argument :card_type, :atom, allow_nil?: false
      filter expr(card_type == ^arg(:card_type))
    end

    read :by_aspect do
      argument :aspect, :atom, allow_nil?: false
      filter expr(aspect == ^arg(:aspect))
    end

    read :by_set do
      argument :set_code, :string, allow_nil?: false
      filter expr(set_code == ^arg(:set_code))
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
      argument :pack_code, :string, allow_nil?: false
      filter expr(pack_code == ^arg(:pack_code))
    end

    read :by_faction do
      argument :faction_code, :string, allow_nil?: false
      filter expr(faction_code == ^arg(:faction_code))
    end

    read :by_card_set do
      argument :card_set_code, :string, allow_nil?: false
      filter expr(card_set_code == ^arg(:card_set_code))
    end

    read :linked_cards do
      argument :code, :string, allow_nil?: false
      filter expr(linked_to_code == ^arg(:code) or code == ^arg(:code))
    end

    update :update do
      primary? true

      accept [
        :name,
        :card_type,
        :cost,
        :text,
        :flavor_text,
        :set_code,
        :card_number,
        :quantity,
        :unique,
        :aspect,
        :attack,
        :thwart,
        :defense,
        :hit_points,
        :scheme,
        :recovery,
        :resource_type,
        :resource_count,
        :traits,
        :keywords,
        :stage,
        :boost_icons,
        :hand_size,
        :base_threat,
        :escalation_threat,
        :acceleration_icon,
        :consequential_damage,
        # MarvelCDB fields
        :code,
        :pack_code,
        :pack_name,
        :real_name,
        :subname,
        :type_code,
        :type_name,
        :faction_code,
        :faction_name,
        :card_set_code,
        :card_set_name,
        :card_set_type_name_code,
        :position,
        :set_position,
        :linked_to_code,
        :linked_to_name,
        :deck_limit,
        :resource_energy,
        :resource_physical,
        :resource_mental,
        :resource_wild,
        :real_text,
        :boost,
        :cost_per_hero,
        :health_per_hero,
        :thwart_cost,
        :attack_cost,
        :defense_cost,
        :recover_cost,
        :attack_star,
        :thwart_star,
        :defense_star,
        :health_star,
        :recover_star,
        :scheme_star,
        :boost_star,
        :threat_star,
        :escalation_threat_star,
        :threat,
        :threat_fixed,
        :base_threat_fixed,
        :escalation_threat_fixed,
        :hidden,
        :permanent,
        :double_sided,
        :octgn_id,
        :url,
        :imagesrc,
        :illustrator,
        :errata,
        :spoiler,
        :meta,
        :back_text,
        :back_flavor,
        :back_name,
        :backimagesrc
      ]
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    # MarvelCDB Core Identity Fields (temporarily nullable until data import)
    attribute :code, :string do
      allow_nil? true
      public? true
    end

    attribute :pack_code, :string do
      allow_nil? true
      public? true
    end

    attribute :pack_name, :string do
      allow_nil? true
      public? true
    end

    attribute :real_name, :string do
      public? true
    end

    attribute :subname, :string do
      public? true
    end

    attribute :card_type, :atom do
      allow_nil? false
      public? true

      constraints one_of: [
                    :hero,
                    :alter_ego,
                    :villain,
                    :main_scheme,
                    :side_scheme,
                    :ally,
                    :event,
                    :resource,
                    :upgrade,
                    :support,
                    :minion,
                    :treachery,
                    :attachment,
                    :environment,
                    :obligation
                  ]
    end

    # MarvelCDB Card Classification
    attribute :type_code, :string do
      allow_nil? false
      public? true
    end

    attribute :type_name, :string do
      allow_nil? false
      public? true
    end

    attribute :faction_code, :string do
      allow_nil? false
      public? true
    end

    attribute :faction_name, :string do
      allow_nil? false
      public? true
    end

    attribute :card_set_code, :string do
      public? true
    end

    attribute :card_set_name, :string do
      public? true
    end

    attribute :card_set_type_name_code, :string do
      public? true
    end

    attribute :cost, :integer do
      public? true
      constraints min: 0
    end

    attribute :text, :string do
      public? true
    end

    attribute :real_text, :string do
      public? true
    end

    attribute :flavor_text, :string do
      public? true
    end

    attribute :set_code, :string do
      allow_nil? false
      public? true
    end

    attribute :card_number, :string do
      allow_nil? false
      public? true
    end

    # MarvelCDB Positioning & Relationships
    attribute :position, :integer do
      allow_nil? false
      public? true
    end

    attribute :set_position, :integer do
      public? true
    end

    attribute :linked_to_code, :string do
      public? true
    end

    attribute :linked_to_name, :string do
      public? true
    end

    attribute :deck_limit, :integer do
      allow_nil? false
      public? true
      default 1
      constraints min: 0
    end

    attribute :quantity, :integer do
      allow_nil? false
      public? true
      default 1
      constraints min: 1
    end

    attribute :unique, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :aspect, :atom do
      public? true
      constraints one_of: [:justice, :leadership, :aggression, :protection, :basic]
    end

    attribute :attack, :integer do
      public? true
      constraints min: 0
    end

    attribute :thwart, :integer do
      public? true
      constraints min: 0
    end

    attribute :defense, :integer do
      public? true
      constraints min: 0
    end

    attribute :hit_points, :integer do
      public? true
      constraints min: 1
    end

    attribute :scheme, :integer do
      public? true
      constraints min: 0
    end

    attribute :recovery, :integer do
      public? true
      constraints min: 0
    end

    # MarvelCDB Enhanced Resource System
    attribute :resource_energy, :integer do
      allow_nil? false
      public? true
      default 0
      constraints min: 0
    end

    attribute :resource_physical, :integer do
      allow_nil? false
      public? true
      default 0
      constraints min: 0
    end

    attribute :resource_mental, :integer do
      allow_nil? false
      public? true
      default 0
      constraints min: 0
    end

    attribute :resource_wild, :integer do
      allow_nil? false
      public? true
      default 0
      constraints min: 0
    end

    # Legacy resource fields (keep for backward compatibility)
    attribute :resource_type, :atom do
      public? true
      constraints one_of: [:energy, :mental, :physical, :wild]
    end

    attribute :resource_count, :integer do
      allow_nil? false
      public? true
      default 0
      constraints min: 0
    end

    attribute :traits, {:array, :string} do
      allow_nil? false
      public? true
      default []
    end

    attribute :keywords, {:array, :string} do
      allow_nil? false
      public? true
      default []
    end

    attribute :stage, :integer do
      public? true
      constraints min: 1
    end

    attribute :boost_icons, :integer do
      allow_nil? false
      public? true
      default 0
      constraints min: 0
    end

    attribute :hand_size, :integer do
      public? true
      constraints min: 1
    end

    attribute :base_threat, :integer do
      public? true
      constraints min: 0
    end

    attribute :escalation_threat, :integer do
      public? true
      constraints min: 1
    end

    attribute :acceleration_icon, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :consequential_damage, :integer do
      public? true
      constraints min: 0
    end

    # MarvelCDB Game Mechanics Fields
    attribute :boost, :integer do
      public? true
      constraints min: 0
    end

    attribute :cost_per_hero, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :health_per_hero, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :thwart_cost, :integer do
      public? true
      constraints min: 0
    end

    attribute :attack_cost, :integer do
      public? true
      constraints min: 0
    end

    attribute :defense_cost, :integer do
      public? true
      constraints min: 0
    end

    attribute :recover_cost, :integer do
      public? true
      constraints min: 0
    end

    # MarvelCDB Star Rating System
    attribute :attack_star, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :thwart_star, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :defense_star, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :health_star, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :recover_star, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :scheme_star, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :boost_star, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :threat_star, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :escalation_threat_star, :boolean do
      allow_nil? false
      public? true
      default false
    end

    # MarvelCDB Enhanced Threat System
    attribute :threat, :integer do
      public? true
      constraints min: 0
    end

    attribute :threat_fixed, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :base_threat_fixed, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :escalation_threat_fixed, :boolean do
      allow_nil? false
      public? true
      default false
    end

    # MarvelCDB Card State Flags
    attribute :hidden, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :permanent, :boolean do
      allow_nil? false
      public? true
      default false
    end

    attribute :double_sided, :boolean do
      allow_nil? false
      public? true
      default false
    end

    # MarvelCDB Metadata & References
    attribute :octgn_id, :string do
      public? true
    end

    attribute :url, :string do
      public? true
    end

    attribute :imagesrc, :string do
      public? true
    end

    attribute :illustrator, :string do
      public? true
    end

    attribute :errata, :string do
      public? true
    end

    attribute :spoiler, :integer do
      public? true
    end

    attribute :meta, :map do
      public? true
    end

    # MarvelCDB Double-sided Card Fields
    attribute :back_text, :string do
      public? true
    end

    attribute :back_flavor, :string do
      public? true
    end

    attribute :back_name, :string do
      public? true
    end

    attribute :backimagesrc, :string do
      public? true
    end

    timestamps()
  end

  identities do
    identity :unique_marvelcdb_code, [:code]
    identity :unique_card_in_pack, [:pack_code, :position]
    identity :unique_card_in_set, [:set_code, :card_number]
  end
end
