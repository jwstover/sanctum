defmodule Sanctum.Events.Group do
  @moduledoc """
  A group: 1-4 players sharing one game area (table). The roster unit the
  event's global thresholds are derived from (player counts sum into Loki's HP;
  the group count drives the Worlds Collide target).

  Each group picks its own difficulty and reports whether it has finished its
  final player phase — the flag the endgame loss check keys off once Worlds
  Collide reaches its target. (Identities are never defeated in this scenario:
  Mischief and Mayhem flips a would-be-defeated identity to alter-ego at 1 HP
  and adds 1 threat to Worlds Collide instead, so there is no survival count.)

  A group can also have The Mangog minion and/or the Door Between Worlds side
  scheme in play (each group in a pod may have its own copy). Both carry the
  per-group icon, so their values scale with the number of groups in the pod:
  The Mangog has `10 × pod-groups` hit points and Door Between Worlds enters
  with `7 × pod-groups` threat (thwarted down to 0). Any player in the pod may
  interact with them, but the counter lives on the group whose area holds it.
  """
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Events,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "event_groups"
    repo Sanctum.Repo

    references do
      reference :pod, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :pod_id, :player_count, :difficulty]
    end

    update :update do
      primary? true

      accept [
        :name,
        :player_count,
        :difficulty,
        :status,
        :mangog_active,
        :mangog_hp,
        :door_active,
        :door_threat
      ]
    end

    # Signed adjustment to The Mangog's hit points, clamped to
    # [0, 10 × pod-groups].
    update :adjust_mangog_hp do
      require_atomic? false
      argument :amount, :integer, allow_nil?: false

      change fn changeset, _context ->
        amount = Ash.Changeset.get_argument(changeset, :amount)
        group = Ash.load!(changeset.data, [:mangog_hp_max])
        max = group.mangog_hp_max || 0
        new_hp = (changeset.data.mangog_hp || 0) |> Kernel.+(amount) |> max(0) |> min(max)

        Ash.Changeset.change_attribute(changeset, :mangog_hp, new_hp)
      end
    end

    # Signed adjustment to Door Between Worlds threat, clamped to
    # [0, 7 × pod-groups]. (The scheme is thwarted down toward 0.)
    update :adjust_door_threat do
      require_atomic? false
      argument :amount, :integer, allow_nil?: false

      change fn changeset, _context ->
        amount = Ash.Changeset.get_argument(changeset, :amount)
        group = Ash.load!(changeset.data, [:door_threat_max])
        max = group.door_threat_max || 0
        new_threat = (changeset.data.door_threat || 0) |> Kernel.+(amount) |> max(0) |> min(max)

        Ash.Changeset.change_attribute(changeset, :door_threat, new_threat)
      end
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false

    attribute :player_count, :integer, public?: true, allow_nil?: false, default: 1

    attribute :difficulty, :atom,
      constraints: [one_of: [:standard, :expert]],
      public?: true,
      allow_nil?: false,
      default: :standard

    attribute :status, :atom,
      constraints: [one_of: [:playing, :phases_ended]],
      public?: true,
      allow_nil?: false,
      default: :playing

    attribute :mangog_active, :boolean, public?: true, allow_nil?: false, default: false
    attribute :mangog_hp, :integer, public?: true, allow_nil?: false, default: 0

    attribute :door_active, :boolean, public?: true, allow_nil?: false, default: false
    attribute :door_threat, :integer, public?: true, allow_nil?: false, default: 0

    timestamps()
  end

  relationships do
    belongs_to :pod, Sanctum.Events.Pod, public?: true, allow_nil?: false
  end

  calculations do
    # Per-group icon: both counters scale with the number of groups in the pod
    # this group belongs to.
    calculate :mangog_hp_max, :integer, expr(pod.groups_count * 10)
    calculate :door_threat_max, :integer, expr(pod.groups_count * 7)
  end
end
