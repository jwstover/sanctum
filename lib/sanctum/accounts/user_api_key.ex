defmodule Sanctum.Accounts.UserApiKey do
  @moduledoc """
  A user's own third-party API key, supplied for features where the user brings
  their own compute (BYOK).

  Today the only provider is `:anthropic`, used by the homebrew "Fill from
  image" extractor (`Sanctum.CardVision`) — the user pays Anthropic directly and
  Sanctum never charges for extraction. The `key` is encrypted at rest via
  `AshCloak`/`Sanctum.Vault` (stored as `encrypted_key`, decrypted only when the
  `key` calculation is explicitly loaded); `key_hint` holds the last four
  characters in the clear for display.

  Keys are private by construction: reads filter to the owning actor (a nil
  actor sees nothing) and writes can only relate to the actor — there is no
  admin read path for a secret.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshCloak]

  postgres do
    table "user_api_keys"
    repo Sanctum.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  cloak do
    vault(Sanctum.Vault)
    attributes [:key]
  end

  actions do
    defaults [:read, :destroy]

    # Idempotent: (re-)storing a validated key replaces it in place. The
    # AshCloak extension turns the accepted `:key` into an argument it encrypts
    # into `encrypted_key`; `last_validated_at` is stamped on every write.
    create :upsert_key do
      accept [:provider, :key, :key_hint]

      change relate_actor(:user)
      change set_attribute(:last_validated_at, &DateTime.utc_now/0)

      upsert? true
      upsert_identity :unique_user_provider
      upsert_fields [:encrypted_key, :key_hint, :last_validated_at]
    end

    read :by_provider do
      argument :provider, :atom, allow_nil?: false

      filter expr(user_id == ^actor(:id) and provider == ^arg(:provider))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if relates_to_actor_via(:user)
    end

    policy action_type(:create) do
      authorize_if relating_to_actor(:user)
    end

    policy action_type([:update, :destroy]) do
      authorize_if relates_to_actor_via(:user)
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :provider, :atom do
      public? true
      allow_nil? false
      default :anthropic
      constraints one_of: [:anthropic]
    end

    # Encrypted at rest (renamed to `encrypted_key` by AshCloak); load the `key`
    # calculation to decrypt.
    attribute :key, :string do
      allow_nil? false
    end

    # Last four characters, in the clear, for masked display (e.g. "…Ab12").
    attribute :key_hint, :string do
      public? true
      allow_nil? false
    end

    attribute :last_validated_at, :utc_datetime_usec do
      public? true
    end

    timestamps()
  end

  relationships do
    belongs_to :user, Sanctum.Accounts.User do
      allow_nil? false
    end
  end

  identities do
    identity :unique_user_provider, [:user_id, :provider]
  end
end
