defmodule Sanctum.Accounts.McdbCredential do
  @moduledoc """
  A user's OAuth2 credential for MarvelCDB, obtained through the
  authorization-code flow and used to act on their behalf against MarvelCDB's
  `/api/oauth2` deck endpoints (publishing a Sanctum-authored deck back to the
  site).

  Deliberately *not* stored in `Sanctum.Accounts.UserIdentity`: that table is
  owned by AshAuthentication and keyed by `(strategy, uid)`, but MarvelCDB's
  OAuth API exposes no user-info endpoint, so there is no `uid` to key on. A
  placeholder would collide across users on that unique identity — hence a
  resource of our own.

  Both tokens are encrypted at rest via `AshCloak`/`Sanctum.Vault`, the same as
  `Sanctum.Accounts.UserApiKey.key` — load the `access_token`/`refresh_token`
  calculations explicitly to decrypt. Credentials are private by construction:
  reads filter to the owning actor (a nil actor sees nothing) and writes can
  only relate to the actor.
  """

  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshCloak]

  postgres do
    table "mcdb_credentials"
    repo Sanctum.Repo

    references do
      reference :user, on_delete: :delete
    end
  end

  cloak do
    vault(Sanctum.Vault)
    attributes [:access_token, :refresh_token]
  end

  actions do
    defaults [:read, :destroy]

    # Idempotent: reconnecting replaces the stored grant in place, so a user who
    # re-authorizes doesn't accumulate credentials. AshCloak turns the accepted
    # token attributes into arguments it encrypts into `encrypted_*`, which is
    # why those are the names listed in `upsert_fields`.
    create :upsert_credential do
      accept [:access_token, :refresh_token, :expires_at]

      change relate_actor(:user)

      upsert? true
      upsert_identity :unique_user
      upsert_fields [:encrypted_access_token, :encrypted_refresh_token, :expires_at]
    end

    read :for_actor do
      description "The calling actor's MarvelCDB credential, if they've connected one."
      get? true

      filter expr(user_id == ^actor(:id))
    end

    # Used after a refresh-token exchange. Not atomic: AshCloak encrypts through
    # a change, which can't run as an atomic update.
    update :rotate_tokens do
      accept [:access_token, :refresh_token, :expires_at]
      require_atomic? false
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

    # Encrypted at rest (renamed to `encrypted_access_token` by AshCloak); load
    # the `access_token` calculation to decrypt.
    attribute :access_token, :string do
      allow_nil? false
    end

    # MarvelCDB issues clients the `refresh_token` grant alongside
    # `authorization_code`, but nothing guarantees a refresh token comes back on
    # every exchange — a credential without one simply has to be reconnected by
    # hand once it expires.
    attribute :refresh_token, :string

    attribute :expires_at, :utc_datetime_usec do
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
    identity :unique_user, [:user_id]
  end
end
