defmodule Sanctum.Games.GameVillain do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "game_villains"
    repo Sanctum.Repo

    references do
      reference :game, on_delete: :delete, on_update: :update
    end
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

    update :advance_stage do
      require_atomic? false

      change fn changeset, _context ->
        game_villain = changeset.data

        # Load the villain with all its stage sides
        villain = Sanctum.Villains.get_villain!(game_villain.villain_id, load: [:stage_sides])

        current_stage =
          if game_villain.active_side_id do
            Enum.find(villain.stage_sides, &(&1.id == game_villain.active_side_id))
          else
            nil
          end

        next_stage_number = if current_stage, do: current_stage.stage + 1, else: 1

        next_stage_side =
          villain.stage_sides
          |> Enum.filter(&(&1.stage == next_stage_number))
          |> Enum.find(&(&1.is_primary_side == true))

        if next_stage_side do
          # Load the card for the next stage
          next_stage_card = Sanctum.Games.get_card!(next_stage_side.card_id)

          changeset
          |> Ash.Changeset.change_attribute(:card_id, next_stage_card.id)
          |> Ash.Changeset.change_attribute(:active_side_id, next_stage_side.id)
        else
          changeset
        end
      end
    end

    update :flip_stage do
      require_atomic? false

      change Sanctum.Games.Changes.FlipToNextSide
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
    belongs_to :villain, Sanctum.Villains.Villain, public?: true, allow_nil?: false

    belongs_to :card, Sanctum.Games.Card do
      public? true
      allow_nil? true
    end

    belongs_to :active_side, Sanctum.Games.CardSide do
      public? true
      allow_nil? true
    end
  end
end
