defmodule Sanctum.Homebrew.HomebrewProject do
  @moduledoc """
  A creator's homebrew workspace — a private folder of `Sanctum.Homebrew.HomebrewSet`s,
  readable only by its creator. Nothing outward-facing reads it: the set is
  the published unit (name, slug, kind, visibility, maturity, tags), and custom
  content (`Card`/`CardAlt`/`Aspect` rows with `origin: :custom`) hangs off a
  set, reaching its project only through that set.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Homebrew,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "homebrew_projects"
    repo Sanctum.Repo

    references do
      reference :creator, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:name, :description, :attestation]

      change relate_actor(:creator)

      validate attribute_equals(:attestation, true) do
        message "you must attest this is your own work or shared with the creator's permission"
      end
    end

    update :update do
      primary? true
      require_atomic? false

      accept [:name, :description]
    end

    destroy :destroy do
      primary? true
    end

    read :for_creator do
      filter expr(creator_id == ^actor(:id))
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # A project is a private workspace: only its creator reads it. Publishing
    # is per set — custom-content visibility follows the set, not the project.
    policy action_type(:read) do
      authorize_if expr(creator_id == ^actor(:id))
    end

    policy action_type(:create) do
      authorize_if relating_to_actor(:creator)
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:creator)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string, public?: true, allow_nil?: false

    # Markdown, rendered on the project page.
    attribute :description, :string, public?: true

    # Upload attestation: "my own work, or shared with the creator's
    # permission". Required true at creation (IP posture).
    attribute :attestation, :boolean, public?: true, allow_nil?: false, default: false

    timestamps()
  end

  relationships do
    belongs_to :creator, Sanctum.Accounts.User do
      public? true
      allow_nil? false
    end

    # Content hangs off sets, never the project directly — counts reach it
    # through them.
    has_many :sets, Sanctum.Homebrew.HomebrewSet do
      destination_attribute :homebrew_project_id
      public? true
    end
  end

  aggregates do
    count :card_count, [:sets, :cards]
    count :alt_count, [:sets, :card_alts]
  end
end
