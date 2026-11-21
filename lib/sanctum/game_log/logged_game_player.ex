defmodule Sanctum.GameLog.LoggedGamePlayer do
  @moduledoc """
  One player's hero + aspect within a `LoggedGame`. Only ever created through
  the parent's `manage_relationship` — no independent listing interface.
  """
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.GameLog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "logged_game_players"
    repo Sanctum.Repo

    references do
      reference :logged_game, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:hero_id, :aspect, :logged_game_id]
    end

    # Required by the parent's `direct_control` manage_relationship, though the
    # v1 UI never edits a logged game.
    update :update do
      primary? true
      accept [:hero_id, :aspect]
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if relates_to_actor_via([:logged_game, :user])
    end

    policy action_type(:create) do
      authorize_if Sanctum.GameLog.Checks.LoggedGameOwnedByActor
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via([:logged_game, :user])
    end
  end

  attributes do
    uuid_v7_primary_key :id

    # An aspect key referencing Sanctum.Games.Aspect (nilable — mirrors
    # CardSide.aspect; no enforced DB FK).
    attribute :aspect, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :logged_game, Sanctum.GameLog.LoggedGame do
      allow_nil? false
    end

    belongs_to :hero, Sanctum.Heroes.Hero do
      public? true
      allow_nil? false
    end

    belongs_to :aspect_def, Sanctum.Games.Aspect do
      source_attribute :aspect
      destination_attribute :key
      attribute_type :string
      define_attribute? false
      allow_nil? true
      public? true
    end
  end
end
