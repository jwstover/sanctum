defmodule Sanctum.Games.Changes.CreateGameSchemeCards do
  @moduledoc """
  During `Game.create`, creates a `GameCard` in the `:main_scheme` zone for each
  of the scenario's main scheme cards.

  Main schemes are represented as ordinary `GameCard`s (owned by `game_id`) so
  they stay consistent with side schemes, which are already `GameCard`s in the
  `:side_scheme` zone. The initial `threat` comes from each scheme's primary
  side `base_threat`; `max_threat`/`escalation_threat` are read from the active
  side (`CardSide`) when needed rather than stored on the `GameCard`.
  """

  alias Ash.Changeset

  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    Changeset.after_action(changeset, fn _changeset, game ->
      create_scheme_cards(game)
      {:ok, game}
    end)
  end

  defp create_scheme_cards(game) do
    case game.scenario_id do
      scenario_id when is_binary(scenario_id) ->
        %{main_schemes: main_schemes} =
          Sanctum.Games.get_scenario!(scenario_id, load: [main_schemes: [:primary_side]])

        main_schemes
        |> Enum.with_index()
        |> Enum.each(fn {scheme, index} ->
          side = scheme.primary_side

          %{
            card_id: scheme.id,
            game_id: game.id,
            zone: :main_scheme,
            order: index,
            threat: base_threat_value(side)
          }
          |> then(&Ash.Changeset.for_create(Sanctum.Games.GameCard, :create, &1))
          |> Ash.create!(domain: Sanctum.Games)
        end)

      _ ->
        :ok
    end
  end

  defp base_threat_value(%{base_threat: %{value: value}}) when not is_nil(value), do: value
  defp base_threat_value(_), do: 0
end
