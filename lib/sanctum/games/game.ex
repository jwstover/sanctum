defmodule Sanctum.Games.Game do
  @moduledoc false

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "games"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, create: :*]
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id
  end

  relationships do
    belongs_to :hero, Sanctum.Games.Card do
      public? true
    end

    belongs_to :villian, Sanctum.Games.Card do
      public? true
    end

    belongs_to :main_scheme, Sanctum.Games.Card do
      public? true
    end
  end
end
