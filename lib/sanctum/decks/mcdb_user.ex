defmodule Sanctum.Decks.McdbUser do
  @moduledoc """
  A MarvelCDB deck author. Imported decks carry only a numeric MarvelCDB
  `user_id` (the API exposes no username and has no public user endpoint), so
  this record preserves authorship. When a Sanctum user later links their
  MarvelCDB account, `sanctum_user` is set once and every deck by that author
  resolves to them.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Decks,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "mcdb_users"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, create: :*]

    create :find_or_create do
      accept [:mcdb_user_id, :username]
      upsert? true
      upsert_identity :unique_mcdb_user_id
    end
  end

  policies do
    policy always() do
      authorize_if always()
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :mcdb_user_id, :integer, public?: true, allow_nil?: false
    attribute :username, :string, public?: true

    timestamps()
  end

  relationships do
    belongs_to :sanctum_user, Sanctum.Accounts.User do
      public? true
    end

    has_many :decks, Sanctum.Decks.Deck
  end

  identities do
    identity :unique_mcdb_user_id, [:mcdb_user_id]
  end
end
