defmodule Sanctum.Accounts.User do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication, Sanctum.Accounts.Strategies.Discord]

  authentication do
    add_ons do
      log_out_everywhere do
        apply_on_password_change? true
      end

      confirmation :confirm_new_user do
        monitor_fields [:email]
        confirm_on_create? true
        confirm_on_update? false
        require_interaction? true
        confirmed_at_field :confirmed_at

        # :register_with_google is auto-confirmed (Google verifies emails) but
        # the add-on's hijack filter still applies to its upsert: it cannot
        # absorb an existing *unconfirmed* password registration for the same
        # email, and auto-confirmation is what writes confirmed_at on conflict.
        # :create is the system-only action (fixtures, seeds, bootstrap) —
        # without it here, creating a user emails them a confirmation link.
        auto_confirm_actions [
          :create,
          :register_with_google,
          :register_with_discord,
          :sign_in_with_magic_link,
          :reset_password_with_token
        ]

        sender Sanctum.Accounts.User.Senders.SendNewUserConfirmationEmail
      end
    end

    tokens do
      enabled? true
      token_resource Sanctum.Accounts.Token
      signing_secret Sanctum.Secrets
      store_all_tokens? true
      require_token_presence_for_authentication? true
    end

    strategies do
      # magic_link do
      #   identity_field :email
      #   registration_enabled? true
      #   require_interaction? true
      #
      #   sender Sanctum.Accounts.User.Senders.SendMagicLinkEmail
      # end

      google do
        client_id Sanctum.Secrets
        redirect_uri Sanctum.Secrets
        client_secret Sanctum.Secrets
        identity_resource Sanctum.Accounts.UserIdentity
      end

      discord do
        client_id Sanctum.Secrets
        redirect_uri Sanctum.Secrets
        client_secret Sanctum.Secrets
        identity_resource Sanctum.Accounts.UserIdentity
      end

      password :password do
        identity_field :email
        hash_provider AshAuthentication.BcryptProvider

        # Registrations must confirm their email before signing in — combined
        # with the confirmation add-on's hijack filter this is what makes an
        # unconfirmed squat on someone else's address worthless.
        require_confirmed_with :confirmed_at

        resettable do
          sender Sanctum.Accounts.User.Senders.SendPasswordResetEmail
          # these configurations will be the default in a future release
          password_reset_action_name :reset_password_with_token
          request_password_reset_action_name :request_password_reset_token
        end
      end

      remember_me :remember_me
    end
  end

  postgres do
    table "users"
    repo Sanctum.Repo
  end

  field_policies do
    # Cover `admin`/`hashed_password` (public? false) too — with reads open,
    # the default (:show) would return them on any authorized read.
    private_fields :include

    # AshAuthentication's own reads (sign-in preparations, session hydration
    # via get_by_subject) run with a nil actor but must see every field —
    # the policy-level bypass above does not extend to field policies.
    field_policy_bypass :* do
      authorize_if AshAuthentication.Checks.AshAuthenticationInteraction
    end

    field_policy [:email, :confirmed_at, :admin, :hashed_password] do
      authorize_if expr(id == ^actor(:id))
      authorize_if actor_attribute_equals(:admin, true)
    end

    field_policy :* do
      authorize_if always()
    end
  end

  actions do
    defaults [:read]

    create :create do
      primary? true
      accept [:email, :confirmed_at, :username, :avatar_url]
    end

    update :set_admin do
      description "Grant or revoke admin. System-only; callers use authorize?: false."
      accept [:admin]
    end

    update :set_avatar do
      description "System-only avatar writes (OAuth backfill). Callers use authorize?: false."
      accept [:avatar_url]
    end

    read :get_by_subject do
      description "Get a user by the subject claim in a JWT"
      argument :subject, :string, allow_nil?: false
      get? true
      prepare AshAuthentication.Preparations.FilterBySubject
    end

    read :get_by_email do
      description "Looks up a user by their email"
      get? true

      argument :email, :ci_string do
        allow_nil? false
      end

      filter expr(email == ^arg(:email))
    end

    create :sign_in_with_magic_link do
      description "Sign in or register a user with magic link."

      argument :token, :string do
        description "The token from the magic link that was sent to the user"
        allow_nil? false
      end

      upsert? true
      upsert_identity :unique_email
      upsert_fields [:email]

      # Uses the information from the token to create or sign in the user
      change AshAuthentication.Strategy.MagicLink.SignInChange

      metadata :token, :string do
        allow_nil? false
      end
    end

    action :request_magic_link do
      argument :email, :ci_string do
        allow_nil? false
      end

      run AshAuthentication.Strategy.MagicLink.Request
    end

    create :register_with_google do
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false
      upsert? true
      upsert_identity :unique_email

      change AshAuthentication.GenerateTokenChange

      # Required if you have the `identity_resource` configuration enabled.
      change AshAuthentication.Strategy.OAuth2.IdentityChange

      change fn changeset, _ ->
        user_info = Ash.Changeset.get_argument(changeset, :user_info)

        changeset
        |> Ash.Changeset.change_attributes(Map.take(user_info, ["email"]))
        |> seed_avatar(user_info)
      end

      change Sanctum.Accounts.User.Changes.BackfillAvatar

      # Required if you're using the password & confirmation strategies
      upsert_fields []
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
    end

    create :register_with_discord do
      argument :user_info, :map, allow_nil?: false
      argument :oauth_tokens, :map, allow_nil?: false
      upsert? true
      upsert_identity :unique_email

      change AshAuthentication.GenerateTokenChange

      # Required if you have the `identity_resource` configuration enabled.
      change AshAuthentication.Strategy.OAuth2.IdentityChange

      change fn changeset, _ ->
        user_info = Ash.Changeset.get_argument(changeset, :user_info)

        # Discord allows unverified account emails. This action is
        # auto-confirmed, so absorbing one into the unique_email upsert would
        # hand out a confirmed account for an address the Discord user never
        # proved they own — the same takeover shape #204 closed. (Assent
        # normalizes Discord's `verified` field to `email_verified`.)
        if user_info["email_verified"] do
          changeset
          |> Ash.Changeset.change_attributes(Map.take(user_info, ["email"]))
          |> seed_avatar(discord_avatar_info(user_info))
        else
          Ash.Changeset.add_error(changeset,
            field: :email,
            message: "your Discord account's email address is not verified"
          )
        end
      end

      change Sanctum.Accounts.User.Changes.BackfillAvatar

      # Required if you're using the password & confirmation strategies
      upsert_fields []
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
    end

    update :update_profile do
      description "Self-service profile edits (username claim). Avatar editing lands with the settings page."

      # The username match validation can't run atomically.
      require_atomic? false
      accept [:username]

      validate match(:username, ~r/^[a-zA-Z0-9_]{3,20}$/) do
        message "3–20 characters: letters, numbers, and underscores only"
      end
    end

    update :change_password do
      # Use this action to allow users to change their password by providing
      # their current password and a new password.

      require_atomic? false
      accept []
      argument :current_password, :string, sensitive?: true, allow_nil?: false

      argument :password, :string,
        sensitive?: true,
        allow_nil?: false,
        constraints: [min_length: 8]

      argument :password_confirmation, :string, sensitive?: true, allow_nil?: false

      validate confirm(:password, :password_confirmation)

      validate {AshAuthentication.Strategy.Password.PasswordValidation,
                strategy_name: :password, password_argument: :current_password}

      change {AshAuthentication.Strategy.Password.HashPasswordChange, strategy_name: :password}
      change Sanctum.Accounts.User.Changes.NotifyPasswordChanged
    end

    read :sign_in_with_password do
      description "Attempt to sign in using a email and password."
      get? true

      argument :email, :ci_string do
        description "The email to use for retrieving the user."
        allow_nil? false
      end

      argument :password, :string do
        description "The password to check for the matching user."
        allow_nil? false
        sensitive? true
      end

      # Rate limit before the bcrypt check runs (see the preparation's docs).
      prepare Sanctum.Accounts.Preparations.RateLimitSignIn

      # validates the provided email and password and generates a token
      prepare AshAuthentication.Strategy.Password.SignInPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    read :sign_in_with_token do
      # In the generated sign in components, we validate the
      # email and password directly in the LiveView
      # and generate a short-lived token that can be used to sign in over
      # a standard controller action, exchanging it for a standard token.
      # This action performs that exchange. If you do not use the generated
      # liveviews, you may remove this action, and set
      # `sign_in_tokens_enabled? false` in the password strategy.

      description "Attempt to sign in using a short-lived sign in token."
      get? true

      argument :token, :string do
        description "The short-lived sign in token."
        allow_nil? false
        sensitive? true
      end

      # validates the provided sign in token and generates a token
      prepare AshAuthentication.Strategy.Password.SignInWithTokenPreparation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    create :register_with_password do
      description "Register a new user with a email and password."

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      # Sets the email from the argument
      change set_attribute(:email, arg(:email))

      # Hashes the provided password
      change AshAuthentication.Strategy.Password.HashPasswordChange

      # Generates an authentication token for the user
      change AshAuthentication.GenerateTokenChange

      # validates that the password matches the confirmation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      metadata :token, :string do
        description "A JWT that can be used to authenticate the user."
        allow_nil? false
      end
    end

    action :request_registration do
      description """
      Enumeration-safe registration: registers the email if it's free, or
      notifies the address that it already has an account. Returns :ok either
      way so callers can't probe which emails exist. See the implementation
      module for the full contract. Called with authorize?: false — safe by
      construction for anonymous use.
      """

      argument :email, :ci_string do
        allow_nil? false
      end

      argument :password, :string do
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        allow_nil? false
        sensitive? true
      end

      run Sanctum.Accounts.User.Actions.RequestRegistration
    end

    action :request_password_reset_token do
      description "Send password reset instructions to a user if they exist."

      argument :email, :ci_string do
        allow_nil? false
      end

      # creates a reset token and invokes the relevant senders
      run {AshAuthentication.Strategy.Password.RequestPasswordReset, action: :get_by_email}
    end

    update :reset_password_with_token do
      # NotifyPasswordChanged adds an after_action hook, which can't run
      # atomically.
      require_atomic? false

      argument :reset_token, :string do
        allow_nil? false
        sensitive? true
      end

      argument :password, :string do
        description "The proposed password for the user, in plain text."
        allow_nil? false
        constraints min_length: 8
        sensitive? true
      end

      argument :password_confirmation, :string do
        description "The proposed password for the user (again), in plain text."
        allow_nil? false
        sensitive? true
      end

      # validates the provided reset token
      validate AshAuthentication.Strategy.Password.ResetTokenValidation

      # validates that the password matches the confirmation
      validate AshAuthentication.Strategy.Password.PasswordConfirmationValidation

      # Hashes the provided password
      change AshAuthentication.Strategy.Password.HashPasswordChange

      # Generates an authentication token for the user
      change AshAuthentication.GenerateTokenChange

      # Security notification: the owner learns their password changed
      change Sanctum.Accounts.User.Changes.NotifyPasswordChanged
    end
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end

    # Public profile reads: anonymous deck browsing loads deck.owner for
    # attribution. The field policies below keep everything but the public
    # profile fields (username/avatar_url) scoped to self/admin.
    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:update_profile) do
      authorize_if expr(id == ^actor(:id))
    end

    # No catch-all: anything not covered above (creates, other updates,
    # destroys) is forbidden by default. Auth flows ride the bypass; system
    # writes (fixtures, seeds, promote_admin) use authorize?: false.
  end

  attributes do
    uuid_primary_key :id

    attribute :email, :ci_string do
      allow_nil? false
      public? true
    end

    attribute :confirmed_at, :utc_datetime, public?: true, allow_nil?: true

    # Public handle shown on deck/game attribution. Claimed after signup
    # (never required at registration), so nil until the user picks one.
    # Format is enforced by :update_profile (the only user-facing write).
    attribute :username, :ci_string do
      allow_nil? true
      public? true
    end

    # Seeded from Google's `picture` on first OAuth registration; users
    # without one get a deterministic initials-on-gradient fallback in the UI.
    attribute :avatar_url, :string do
      allow_nil? true
      public? true
    end

    # Gates the /cards/* admin pages and Card/CardSide mutations. Not public:
    # never accepted from forms/params, only via the :set_admin action.
    attribute :admin, :boolean do
      allow_nil? false
      default false
      public? false
    end

    # Nil for users who only sign in via OAuth (e.g. Google) or magic link.
    attribute :hashed_password, :string do
      allow_nil? true
      sensitive? true
    end
  end

  identities do
    identity :unique_email, [:email]
    identity :unique_username, [:username]
  end

  # Seeds avatar_url from the provider's user_info on first registration only —
  # `upsert_fields []` means nothing is written on conflict, so a re-login
  # never clobbers an existing profile. Existing users *without* an avatar are
  # handled separately by Changes.BackfillAvatar after the upsert resolves.
  defp seed_avatar(changeset, %{"picture" => picture})
       when is_binary(picture) and picture != "" do
    Ash.Changeset.change_attribute(changeset, :avatar_url, picture)
  end

  defp seed_avatar(changeset, _user_info), do: changeset

  # Assent builds Discord's picture URL by interpolating the avatar hash, so a
  # user without a custom avatar yields a URL ending in "/" — drop it so
  # seed_avatar doesn't store a broken link.
  defp discord_avatar_info(%{"picture" => picture} = user_info) when is_binary(picture) do
    if String.ends_with?(picture, "/"), do: Map.delete(user_info, "picture"), else: user_info
  end

  defp discord_avatar_info(user_info), do: user_info
end
