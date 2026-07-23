defmodule Sanctum.Decks.DeckState do
  @moduledoc """
  Lifecycle phase of a native deck: `:draft` while it's still being built,
  `:final` once the owner locks it in. Publishing requires `:final` — the
  phased flow is draft → finalize → publish.
  """

  use Ash.Type.Enum, values: [:draft, :final]
end
