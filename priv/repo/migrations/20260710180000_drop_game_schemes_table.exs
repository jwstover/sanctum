defmodule Sanctum.Repo.Migrations.DropGameSchemesTable do
  @moduledoc """
  Drops the `game_schemes` table.

  The `Sanctum.Games.GameScheme` resource has been removed; main schemes are now
  represented as `game_cards` in the `:main_scheme` zone. `mix ash.codegen` does
  not emit drop migrations for removed resources (the migration generator only
  snapshots currently-defined resources), so this migration is written by hand
  to match the format produced by `mix ash_postgres.generate_migrations`.
  """

  use Ecto.Migration

  def up do
    drop table(:game_schemes)
  end

  def down do
    create table(:game_schemes, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("uuid_generate_v7()"), primary_key: true
      add :threat, :bigint, null: false, default: 0
      add :max_threat, :bigint
      add :escalation_threat, :bigint
      add :counter, :bigint, null: false, default: 0
      add :is_main_scheme, :boolean

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :game_id,
          references(:games,
            column: :id,
            name: "game_schemes_game_id_fkey",
            type: :uuid,
            prefix: "public",
            on_delete: :delete_all,
            on_update: :update_all
          )

      add :card_id,
          references(:cards,
            column: :id,
            name: "game_schemes_card_id_fkey",
            type: :uuid,
            prefix: "public"
          )

      add :active_side_id,
          references(:card_sides,
            column: :id,
            name: "game_schemes_active_side_id_fkey",
            type: :uuid,
            prefix: "public"
          )
    end
  end
end
