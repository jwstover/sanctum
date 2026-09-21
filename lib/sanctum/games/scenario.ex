defmodule Sanctum.Games.Scenario do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "scenarios"
    repo Sanctum.Repo

    identity_wheres_to_sql unique_official_villain_set: "owner_id IS NULL"

    references do
      reference :owner, on_delete: :nilify
    end
  end

  actions do
    defaults [:read, :destroy]

    read :browse do
      description "The scenario browser: search-language filter (ScenarioFields), sort and offset pagination."

      argument :query, :string, allow_nil?: true
      argument :sort, :string, allow_nil?: true

      pagination offset?: true, default_limit: 24, countable: true, required?: false

      prepare fn query, _context ->
        require Ash.Query

        query
        |> Ash.Query.load([:modular_set_count, :owner, :villain_set])
        |> Sanctum.Search.filter_query(
          Ash.Query.get_argument(query, :query),
          Sanctum.Search.ScenarioFields
        )
        |> then(fn query ->
          # The id tie-breaker keeps offset pages stable (uuid_v7 is time-ordered).
          case Ash.Query.get_argument(query, :sort) do
            "name" -> Ash.Query.sort(query, name: :asc, id: :asc)
            _ -> Ash.Query.sort(query, inserted_at: :desc, id: :desc)
          end
        end)
      end
    end

    read :for_game_setup do
      description "The new-game picker: official scenarios plus the actor's own, by name."

      filter expr(is_nil(owner_id) or owner_id == ^actor(:id))
      prepare build(sort: [name: :asc, id: :asc])
    end

    create :create do
      primary? true
      accept [:name, :description_md, :villain_set_id]
      upsert? true
      upsert_identity :unique_official_villain_set

      argument :modular_sets, {:array, :uuid}

      validate Sanctum.Games.Validations.ValidateVillainSet
      change Sanctum.Games.Changes.SetScenarioSet, only_when_valid?: true
      change manage_relationship(:modular_sets, type: :append_and_remove)
    end

    create :build do
      description "Creates a user-owned scenario for the signed-in user; name defaults to \"<villain set> Scenario\"."
      accept [:villain_set_id, :name, :description_md]

      change relate_actor(:owner)

      validate Sanctum.Games.Validations.ValidateVillainSet
      change Sanctum.Games.Changes.SetScenarioSet, only_when_valid?: true
      change Sanctum.Games.Changes.DefaultScenarioName
    end

    update :rename do
      accept [:name]
      require_atomic? false
    end

    update :set_description do
      accept [:description_md]
      require_atomic? false
    end

    update :set_modular_sets do
      argument :modular_sets, {:array, :uuid}, allow_nil?: false, default: []
      require_atomic? false

      validate Sanctum.Games.Validations.ValidateModularSets
      change manage_relationship(:modular_sets, type: :append_and_remove)
    end
  end

  policies do
    # Admins moderate any scenario, official or user-owned; seeds and tests use authorize?: false.
    bypass [actor_attribute_equals(:admin, true), action_type([:create, :update, :destroy])] do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:build) do
      authorize_if actor_present()
    end

    # Official rows (owner_id nil) never match, so they're immutable for non-admins.
    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:owner)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false
    attribute :description_md, :string, public?: true, allow_nil?: true
    # Derived from villain_set.code; kept as a column for the Card.set joins below.
    attribute :set, :string, public?: true, allow_nil?: false

    timestamps()
  end

  relationships do
    # The villain CardSet, not Villains.Villain: sets like Loki, Marauders and
    # Sinister Six have several Villain rows each.
    belongs_to :villain_set, Sanctum.Catalog.CardSet do
      public? true
      allow_nil? false
    end

    # nil = official scenario.
    belongs_to :owner, Sanctum.Accounts.User do
      public? true
      allow_nil? true
    end

    many_to_many :modular_sets, Sanctum.Catalog.CardSet do
      public? true
      through Sanctum.Games.ScenarioModularSet
      source_attribute_on_join_resource :scenario_id
      destination_attribute_on_join_resource :card_set_id
    end

    has_many :villains, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set
      filter expr(primary_side.type == :villain)
    end

    has_many :main_schemes, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set
      filter expr(primary_side.type == :main_scheme)
    end

    has_many :encounter_cards, Sanctum.Games.Card do
      source_attribute :set
      destination_attribute :set
      filter expr(primary_side.type not in [:villain, :main_scheme])
    end
  end

  calculations do
    # A nil actor compares owner_id to NULL, which matches nothing (loads as nil).
    calculate :mine, :boolean, expr(owner_id == ^actor(:id))

    calculate :official, :boolean, expr(is_nil(owner_id))
  end

  aggregates do
    count :modular_set_count, :modular_sets
  end

  identities do
    # One official scenario per villain set; user-owned scenarios may share a set.
    identity :unique_official_villain_set, [:villain_set_id] do
      where expr(is_nil(owner_id))
    end
  end
end
