defmodule Sanctum.Games.Validations.NoLoggedGames do
  @moduledoc """
  Refuses to destroy a scenario that logged games still reference
  (`logged_games.scenario_id` has no `on_delete`, so Postgres would reject it).
  """

  use Ash.Resource.Validation

  require Ash.Query

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def supports(_opts), do: [Ash.Changeset]

  @impl true
  def validate(changeset, _opts, _context) do
    id = changeset.data.id

    # LoggedGame reads are owner-only; count every user's games.
    count =
      Sanctum.GameLog.LoggedGame
      |> Ash.Query.filter(scenario_id == ^id)
      |> Ash.count!(authorize?: false)

    case count do
      0 -> :ok
      1 -> {:error, message: "This scenario has 1 logged game, so it can't be deleted."}
      n -> {:error, message: "This scenario has #{n} logged games, so it can't be deleted."}
    end
  end
end
