defmodule Sanctum.Events.Pod do
  @moduledoc """
  A pod: a collection of groups (recommended ≤3-4 groups / ≤12-16 players) that
  can help each other via cross-group card effects.

  The pod is a structural grouping and the unit the per-group icon keys off of:
  its `groups_count` scales each group's Mangog / Door Between Worlds maxima.
  Those cards themselves live on the individual groups whose areas hold them.
  """
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Events,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "event_pods"
    repo Sanctum.Repo

    references do
      reference :event, on_delete: :delete, on_update: :update
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:name, :event_id]
    end

    update :update do
      primary? true
      accept [:name]
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

    timestamps()
  end

  relationships do
    belongs_to :event, Sanctum.Events.Event, public?: true, allow_nil?: false
    has_many :groups, Sanctum.Events.Group
  end

  aggregates do
    count :groups_count, :groups
  end
end
