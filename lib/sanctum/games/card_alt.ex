defmodule Sanctum.Games.CardAlt do
  @moduledoc """
  An alternate printing of a canonical `Card`.

  MarvelCDB reprints a card under a new code with `duplicate_of_code` pointing
  back to the original. Rather than create a second `Card` (which would pollute
  the pool and deck resolution), each reprint side is stored as a thin
  `CardAlt` pointing at the canonical card. Deck slots that reference a reprint
  code resolve to the canonical card via this table.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Games,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "card_alts"
    repo Sanctum.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true
      accept [:*]
      upsert? true
      upsert_identity :unique_alt_code
    end

    update :update do
      primary? true
      accept [:*]
    end

    read :by_code do
      argument :code, :string, allow_nil?: false
      filter expr(code == ^arg(:code))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    # Catalog mutations are admin-only; system writes (sync) go through
    # Sanctum.MarvelCdb with authorize?: false.
    policy action_type([:create, :update, :destroy]) do
      authorize_if actor_attribute_equals(:admin, true)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    # The reprint's own side code (e.g. "16021" / "16021a").
    attribute :code, :string, public?: true, allow_nil?: false
    attribute :base_code, :string, public?: true, allow_nil?: false
    attribute :side_identifier, :string, public?: true

    attribute :pack, :string, public?: true
    attribute :set, :string, public?: true
    attribute :image_url, :string, public?: true

    timestamps()
  end

  relationships do
    # The canonical card this is an alternate printing of.
    belongs_to :card, Sanctum.Games.Card do
      public? true
      allow_nil? false
    end
  end

  identities do
    identity :unique_alt_code, [:code]
  end
end
