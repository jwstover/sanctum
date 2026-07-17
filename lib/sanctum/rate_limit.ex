defmodule Sanctum.RateLimit do
  @moduledoc """
  Process-local rate limiter (Hammer, ETS backend).

  Counters are per-node: with multiple Fly machines the effective limit is
  `limit × machines`. That's acceptable for the auth abuse-throttling these
  limits exist for — the ceilings are sized with that slack in mind.
  """

  use Hammer, backend: :ets
end
