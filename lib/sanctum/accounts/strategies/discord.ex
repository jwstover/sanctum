defmodule Sanctum.Accounts.Strategies.Discord do
  @moduledoc """
  Discord OAuth2 strategy for AshAuthentication, mirroring how the built-in
  `google` strategy wraps its Assent module. Backing the generic `oauth2`
  entity with `Assent.Strategy.Discord` matters for one security-relevant
  reason: Assent normalizes Discord's raw `/users/@me` payload (`verified`)
  into the standard `email_verified` claim, which is what both the
  `trust_email_verified?` account-linking check and our own guard in
  `:register_with_discord` key off.

  Registered on `Sanctum.Accounts.User` via its `extensions` list; configure
  with `discord do ... end` in the `strategies` block.
  """

  alias AshAuthentication.Strategy.{Custom, OAuth2}

  @entity OAuth2.dsl()
          |> Map.merge(%{
            name: :discord,
            args: [{:optional, :name, :discord}],
            describe: "Pre-configured OAuth2 strategy for Discord.",
            auto_set_fields: [icon: :discord, assent_strategy: Assent.Strategy.Discord]
          })
          |> Custom.set_defaults(
            base_url: "https://discord.com/api",
            authorize_url: "https://discord.com/oauth2/authorize",
            token_url: "/oauth2/token",
            user_url: "/users/@me",
            authorization_params: [scope: "identify email"],
            auth_method: :client_secret_post,
            trust_email_verified?: true
          )

  use Custom, entity: @entity

  defdelegate transform(strategy, dsl_state), to: OAuth2
  defdelegate verify(strategy, dsl_state), to: OAuth2
end
