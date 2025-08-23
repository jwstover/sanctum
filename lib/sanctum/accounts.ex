defmodule Sanctum.Accounts do
  use Ash.Domain, otp_app: :sanctum, extensions: [AshAdmin.Domain]

  admin do
    show? true
  end

  resources do
    resource Sanctum.Accounts.Token

    resource Sanctum.Accounts.User do
      define :get_user, get_by: :id, action: :read
    end
  end
end
