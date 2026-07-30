defmodule Sanctum.Accounts do
  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Sanctum.Accounts.Token

    resource Sanctum.Accounts.UserIdentity

    resource Sanctum.Accounts.UserApiKey do
      define :upsert_api_key, action: :upsert_key

      define :api_key_for_provider,
        action: :by_provider,
        args: [:provider],
        get?: true,
        not_found_error?: false

      define :destroy_api_key, action: :destroy
    end

    resource Sanctum.Accounts.User do
      define :get_user, get_by: :id, action: :read
      define :get_user_by_email, args: [:email], get?: true, action: :get_by_email
      define :set_admin, args: [:admin], action: :set_admin
    end
  end
end
