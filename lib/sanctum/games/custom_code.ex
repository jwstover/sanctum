defmodule Sanctum.Games.CustomCode do
  @moduledoc """
  Code minting for custom (homebrew) cards.

  Card codes are `custom-<uuid>` — outside MarvelCDB's numeric space, so they
  can never collide with (or be captured by) a catalog-sync upsert. Side codes
  follow the official convention: `<card code><letter>` with letters a..f.
  """

  @side_letters ~w(a b c d e f)

  def side_letters, do: @side_letters

  def mint, do: "custom-" <> Ash.UUID.generate()

  def side_code(card_code, letter) when letter in @side_letters, do: card_code <> letter
end
