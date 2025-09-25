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
    defaults [:read]

    create :create do
      primary? true
      accept [:*]

      change fn changeset, _context ->
        card_id = Ash.Changeset.get_attribute(changeset, :card_id)

        if card_id do
          # Load the card with its sides to set initial active_side
          card = Sanctum.Games.get_card!(card_id, load: [:primary_side])

          if card.primary_side do
            Ash.Changeset.change_attribute(changeset, :active_side_id, card.primary_side.id)
          else
            changeset
          end
        else
          changeset
        end
      end
    end

    update :flip do
      require_atomic? false

      change Sanctum.Games.Changes.FlipToNextSide
    end

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

    attribute :threat, :integer, public?: true, default: 0
    attribute :max_threat, :integer, public?: true
    attribute :escalation_threat, :integer, public?: true
    attribute :counter, :integer, default: 0, public?: true
    attribute :is_main_scheme, :boolean, public?: true

    timestamps()
  end

  relationships do
    belongs_to :game, Sanctum.Games.Game
    belongs_to :card, Sanctum.Games.Card, public?: true

    belongs_to :active_side, Sanctum.Games.CardSide do
      public? true
      allow_nil? true
    end
  end
end
