defmodule Sanctum.GameLog.LoggedGame do
  @moduledoc """
  A single physical (in-person) play of a scenario: hero/aspect per player,
  the villain, modular sets, and (when the scenario offers more than one) the
  main scheme used. Recorded after the fact — there is no live state or zone
  tracking here (see `Sanctum.Games.Game` for the digital smart table).
  """
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.GameLog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Sanctum.GameLog.Changes.SetDefaultMainScheme
  alias Sanctum.GameLog.Changes.SetVillainFromScenario
  alias Sanctum.GameLog.Validations.ValidateMainSchemeChoice

  postgres do
    table "logged_games"
    repo Sanctum.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:played_at, :modular_sets, :scenario_id, :main_scheme_id]

      argument :logged_game_players, {:array, :map}, allow_nil?: false

      change relate_actor(:user)
      change SetVillainFromScenario
      change SetDefaultMainScheme
      change manage_relationship(:logged_game_players, type: :direct_control)

      validate ValidateMainSchemeChoice
    end

    read :for_user do
      filter expr(user_id == ^actor(:id))
      prepare build(sort: [played_at: :desc, inserted_at: :desc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:create) do
      authorize_if relating_to_actor(:user)
    end

    policy action_type(:destroy) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :played_at, :date, public?: true, allow_nil?: false, default: &Date.utc_today/0

    # Snapshot of Sanctum.Catalog.CardSet `code`s used, exactly like
    # Sanctum.Games.Game.modular_sets — a plain string array, not a
    # many-to-many, so the log stays meaningful if catalog rows change later.
    attribute :modular_sets, {:array, :string}, public?: true, allow_nil?: false, default: []

    timestamps()
  end

  relationships do
    belongs_to :user, Sanctum.Accounts.User, allow_nil?: false

    belongs_to :scenario, Sanctum.Games.Scenario, public?: true, allow_nil?: false

    belongs_to :villain, Sanctum.Villains.Villain, public?: true, allow_nil?: false

    belongs_to :main_scheme, Sanctum.Games.Card do
      public? true
      allow_nil? true
    end

    has_many :logged_game_players, Sanctum.GameLog.LoggedGamePlayer do
      public? true
      sort id: :asc
    end
  end
end
