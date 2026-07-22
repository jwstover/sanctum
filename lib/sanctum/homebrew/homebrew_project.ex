defmodule Sanctum.Homebrew.HomebrewProject do
  @moduledoc """
  A creator's homebrew content project — the unit the community shares and
  discovers ("Juri Krasko's Daredevil"), holding custom cards as
  `Sanctum.Games.Card` rows with `origin: :custom`.

  Projects start `:private`; the visibility ladder (`:private → :unlisted →
  :published`) is walked through `:set_visibility` so the future publish flow
  (releases, review gate) can hang off that one action.
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
      accept [
        :name,
        :description,
        :banner_url,
        :content_types,
        :maturity,
        :tags,
        :attestation
      ]

      change relate_actor(:creator)

      validate attribute_equals(:attestation, true) do
        message "you must attest this is your own work or shared with the creator's permission"
      end
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :name,
        :description,
        :banner_url,
        :content_types,
        :maturity,
        :tags
      ]
    end

    # Visibility transitions are their own action so the publish flow
    # (releases, review gate) can add changes/validations here without
    # touching general editing.
    update :set_visibility do
      accept [:visibility]
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

    # Filter checks: non-matching rows are excluded from every read, so a
    # private/unlisted project is invisible — not "forbidden" — to everyone
    # but its creator. Separate checks on purpose: an expr referencing
    # ^actor(:id) collapses to false wholesale under a nil actor, which
    # would otherwise also hide published projects from anonymous reads.
    policy action_type(:read) do
      authorize_if expr(visibility == :published)
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
    attribute :banner_url, :string, public?: true

    attribute :content_types, {:array, Sanctum.Homebrew.ContentType},
      public?: true,
      default: []

    attribute :maturity, Sanctum.Homebrew.Maturity,
      public?: true,
      allow_nil?: false,
      default: :draft

    attribute :visibility, Sanctum.Homebrew.Visibility,
      public?: true,
      allow_nil?: false,
      default: :private

    attribute :tags, {:array, :string}, public?: true, default: []

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

    has_many :cards, Sanctum.Games.Card do
      destination_attribute :homebrew_project_id
      public? true
    end

    has_many :card_alts, Sanctum.Games.CardAlt do
      destination_attribute :homebrew_project_id
      public? true
    end
  end

  aggregates do
    count :card_count, :cards
    count :alt_count, :card_alts
  end
end
