defmodule Sanctum.Repo.Migrations.UpgradeObanToV14 do
  @moduledoc """
  Upgrades the Oban schema to v14 (adds the `suspended` oban_job_state, among
  other changes) to match Oban 2.23. Oban ships its own framework migrations, so
  this is a hand-written Ecto migration rather than an Ash-generated one.
  """

  use Ecto.Migration

  def up, do: Oban.Migration.up(version: 14)

  def down, do: Oban.Migration.down(version: 13)
end
