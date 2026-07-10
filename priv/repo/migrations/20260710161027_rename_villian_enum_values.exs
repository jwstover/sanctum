defmodule Sanctum.Repo.Migrations.RenameVillianEnumValues do
  @moduledoc """
  Data-only migration to correct the "villian" -> "villain" misspelling in
  stored enum values. These values are persisted as TEXT (Ash `one_of` atom
  constraints are app-level only), so `ash.codegen` generates no schema change
  for this rename.
  """

  use Ecto.Migration

  def up do
    execute("UPDATE games SET state = 'villain' WHERE state = 'villian'")

    execute("UPDATE game_cards SET zone = 'villain_play' WHERE zone = 'villian_play'")
  end

  def down do
    execute("UPDATE games SET state = 'villian' WHERE state = 'villain'")

    execute("UPDATE game_cards SET zone = 'villian_play' WHERE zone = 'villain_play'")
  end
end
