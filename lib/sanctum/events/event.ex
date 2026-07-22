defmodule Sanctum.Events.Event do
  @moduledoc """
  A single Epic Multiplayer "God of Lies" event.

  Holds the global clocks the organizer tracks and derives the rulebook
  thresholds from the roster so the organizer never hand-computes them:

    * Loki, God of Lies hit points — start `20 * total_players`, flip at
      `10 * total_players`, win at `0`.
    * Worlds Collide threat — lose when it reaches `2 * total_groups`.
    * Time limit — default 180 minutes.
  """
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Events,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "events"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :time_limit_minutes]
      change relate_actor(:user)
    end

    read :read_for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
      prepare build(sort: [inserted_at: :desc])
    end

    update :update do
      primary? true
      accept [:name, :time_limit_minutes]
    end

    # Restart the countdown from the full time limit.
    update :reset_timer do
      require_atomic? false

      change fn changeset, _context ->
        Ash.Changeset.change_attribute(changeset, :started_at, DateTime.utc_now())
      end
    end

    # Locks the roster in and starts the clocks: seed Loki's HP from the roster,
    # zero out Worlds Collide, stamp the start time.
    update :start do
      require_atomic? false

      change fn changeset, _context ->
        event = Ash.load!(changeset.data, [:total_players], authorize?: false)
        players = event.total_players || 0

        changeset
        |> Ash.Changeset.change_attribute(:status, :running)
        |> Ash.Changeset.change_attribute(:started_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:loki_hp, 20 * players)
        |> Ash.Changeset.change_attribute(:worlds_collide_threat, 0)
        |> Ash.Changeset.change_attribute(:loki_flipped, false)
      end
    end

    # Signed adjustment to Loki's remaining HP (negative = damage recorded by a
    # group). Clamped to [0, 20 * total_players]; flips Loki at the threshold.
    update :adjust_loki_hp do
      require_atomic? false
      argument :amount, :integer, allow_nil?: false

      change fn changeset, _context ->
        amount = Ash.Changeset.get_argument(changeset, :amount)
        event = Ash.load!(changeset.data, [:loki_hp_max, :loki_flip_threshold], authorize?: false)
        max = event.loki_hp_max || 0
        current = changeset.data.loki_hp || max
        new_hp = current |> Kernel.+(amount) |> max(0) |> min(max)

        changeset
        |> Ash.Changeset.change_attribute(:loki_hp, new_hp)
        |> Ash.Changeset.change_attribute(
          :loki_flipped,
          new_hp <= (event.loki_flip_threshold || 0)
        )
      end
    end

    # Signed adjustment to Worlds Collide threat. Clamped to
    # [0, 2 * total_groups].
    update :adjust_worlds_collide do
      require_atomic? false
      argument :amount, :integer, allow_nil?: false

      change fn changeset, _context ->
        amount = Ash.Changeset.get_argument(changeset, :amount)
        event = Ash.load!(changeset.data, [:worlds_collide_target], authorize?: false)
        target = event.worlds_collide_target || 0
        current = changeset.data.worlds_collide_threat || 0
        new_threat = current |> Kernel.+(amount) |> max(0) |> min(target)

        Ash.Changeset.change_attribute(changeset, :worlds_collide_threat, new_threat)
      end
    end
  end

  policies do
    # Admins can moderate any event. System operations run with authorize?: false.
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Any logged-in user may create an event (they become its owner).
    policy action_type(:create) do
      authorize_if actor_present()
    end

    # Only the owner may read, modify, or delete their event and its state.
    policy action_type([:read, :update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false

    attribute :status, :atom,
      constraints: [one_of: [:setup, :running, :complete]],
      public?: true,
      allow_nil?: false,
      default: :setup

    attribute :time_limit_minutes, :integer, public?: true, allow_nil?: false, default: 180

    attribute :started_at, :utc_datetime, public?: true

    # Current remaining HP on Loki, God of Lies. nil until the event starts.
    attribute :loki_hp, :integer, public?: true

    attribute :loki_flipped, :boolean, public?: true, allow_nil?: false, default: false

    attribute :worlds_collide_threat, :integer, public?: true, allow_nil?: false, default: 0

    timestamps()
  end

  relationships do
    belongs_to :user, Sanctum.Accounts.User, public?: true, allow_nil?: false
    has_many :pods, Sanctum.Events.Pod
  end

  calculations do
    # Rulebook thresholds, derived from the roster so the organizer never does
    # the arithmetic by hand.
    calculate :loki_hp_max,
              :integer,
              expr(if(is_nil(total_players), do: 0, else: total_players * 20))

    calculate :loki_flip_threshold,
              :integer,
              expr(if(is_nil(total_players), do: 0, else: total_players * 10))

    calculate :worlds_collide_target, :integer, expr(total_groups * 2)
  end

  aggregates do
    sum :total_players, [:pods, :groups], :player_count
    count :total_groups, [:pods, :groups]
    count :total_pods, :pods
  end
end
