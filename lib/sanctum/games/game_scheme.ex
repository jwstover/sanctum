defmodule Sanctum.Games.GameScheme do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "game_schemes"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, create: :*]

    update :update_threat do
      argument :delta, :integer, allow_nil?: false

      change atomic_update(:threat, expr(threat + ^arg(:delta)))
    end

    update :update_counter do
      argument :delta, :integer, allow_nil?: false

      change atomic_update(:counter, expr(counter + ^arg(:delta)))
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :threat, :integer, public?: true
    attribute :max_threat, :integer, public?: true
    attribute :escalation_threat, :integer, public?: true
    attribute :counter, :integer, default: 0, public?: true
    attribute :is_main_scheme, :boolean, public?: true

    timestamps()
  end

  relationships do
    belongs_to :game, Sanctum.Games.Game
    belongs_to :card, Sanctum.Games.Card, public?: true
  end
end
