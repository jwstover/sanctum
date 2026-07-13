defmodule Sanctum.Accounts do
  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Sanctum.Accounts.Token

    resource Sanctum.Accounts.UserIdentity

    resource Sanctum.Accounts.User do
      define :get_user, get_by: :id, action: :read
      define :get_user_by_email, args: [:email], get?: true, action: :get_by_email
      define :set_admin, args: [:admin], action: :set_admin
    end
  end
end
