defmodule Sanctum.Homebrew.SetReport do
  @moduledoc """
  A signed-in user's report against a public homebrew set — the input to the
  admin moderation queue (`/admin/reports`).

  Only a set the reporter could reach through its link (`:published` or
  `:unlisted`) can be reported (`Validations.SetIsReportable`), and each user
  reports a given set at most once. Reports are admin-only after creation:
  an admin either takes the set down (`HomebrewSet :take_down`, which marks
  the set's open reports `:actioned`) or dismisses the report here.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Homebrew,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "homebrew_set_reports"
    repo Sanctum.Repo

    references do
      # A deleted set takes its reports with it. No extra index: the
      # unique (homebrew_set_id, reporter_id) identity leads with it.
      reference :homebrew_set, on_delete: :delete
      reference :reporter, on_delete: :delete
      reference :resolved_by, on_delete: :nilify
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:homebrew_set_id, :reason, :details]

      change relate_actor(:reporter)

      # After the create policy: looks the set up with authorize?: false.
      validate Sanctum.Homebrew.Validations.SetIsReportable, before_action?: true
    end

    # The moderation queue: open reports, oldest first so nothing starves.
    read :open_queue do
      filter expr(status == :open)

      prepare build(
                load: [reporter: [:username], homebrew_set: [creator: [:username]]],
                sort: [inserted_at: :asc, id: :asc]
              )
    end

    update :dismiss do
      accept []
      require_atomic? false

      change set_attribute(:status, :dismissed)
      change set_attribute(:resolved_at, &DateTime.utc_now/0)
      change relate_actor(:resolved_by)
    end

    # Written by HomebrewSet :take_down (Changes.ActionOpenReports) for every
    # open report on the set it takes down.
    update :mark_actioned do
      accept []
      require_atomic? false

      change set_attribute(:status, :actioned)
      change set_attribute(:resolved_at, &DateTime.utc_now/0)
      change relate_actor(:resolved_by)
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Any signed-in user may file a report; relate_actor stamps them.
    policy action_type(:create) do
      authorize_if relating_to_actor(:reporter)
    end

    # Reading and resolving reports is admin-only (the bypass above).
    policy action_type([:read, :update, :destroy]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :reason, Sanctum.Homebrew.SetReportReason, public?: true, allow_nil?: false

    attribute :details, :string,
      public?: true,
      constraints: [max_length: 2000]

    attribute :status, Sanctum.Homebrew.SetReportStatus,
      public?: true,
      allow_nil?: false,
      default: :open

    attribute :resolved_at, :utc_datetime_usec, public?: true

    timestamps()
  end

  relationships do
    belongs_to :homebrew_set, Sanctum.Homebrew.HomebrewSet do
      public? true
      allow_nil? false
    end

    belongs_to :reporter, Sanctum.Accounts.User do
      public? true
      allow_nil? false
      attribute_writable? false
    end

    belongs_to :resolved_by, Sanctum.Accounts.User do
      public? true
      allow_nil? true
      attribute_writable? false
    end
  end

  identities do
    # One report per user per set — cheap spam protection.
    identity :unique_reporter_set, [:homebrew_set_id, :reporter_id]
  end
end
