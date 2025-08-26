defmodule Sanctum.Games.GameVillian do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "game_villians"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, create: :*]

    update :update do
      primary? true
      accept [:health, :max_health, :attack, :scheme]
    end

    update :change_health do
      argument :amount, :integer, allow_nil?: false

      change atomic_update(
               :health,
               expr(fragment("LEAST(?, GREATEST(0, ? + ?))", max_health, health, ^arg(:amount)))
             )
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :health, :integer, public?: true
    attribute :max_health, :integer, public?: true

    attribute :attack, :integer, public?: true
    attribute :scheme, :integer, public?: true

    timestamps()
  end

  relationships do
    belongs_to :game, Sanctum.Games.Game, public?: true, allow_nil?: false
    belongs_to :card, Sanctum.Games.Card, public?: true, allow_nil?: false
  end
end
