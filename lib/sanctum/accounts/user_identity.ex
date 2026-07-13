defmodule Sanctum.Accounts.UserIdentity do
  use Ash.Resource,
    otp_app: :sanctum,
    domain: Sanctum.Accounts,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshAuthentication.UserIdentity]

  postgres do
    table "user_identities"
    repo Sanctum.Repo
  end

  user_identity do
    user_resource Sanctum.Accounts.User
  end

  policies do
    bypass AshAuthentication.Checks.AshAuthenticationInteraction do
      authorize_if always()
    end
  end
end
