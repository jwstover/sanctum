defmodule Sanctum.Vault do
  @moduledoc """
  Cloak vault for encrypting sensitive attributes at rest (see `AshCloak`).

  Currently backs `Sanctum.Accounts.UserApiKey.key` — a user's own Anthropic
  API key, supplied for the homebrew "Fill from image" extractor (BYOK). The
  ciphers (and the AES key) are configured in `config/runtime.exs`; the key
  comes from the `CLOAK_KEY` env var in prod and a static dev/test key
  otherwise. The key is held **separately from the database** on purpose: a DB
  dump alone (e.g. `scripts/pull_prod_db`) cannot decrypt these values.
  """
  use Cloak.Vault, otp_app: :sanctum
end
