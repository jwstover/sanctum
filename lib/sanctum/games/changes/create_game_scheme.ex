defmodule Sanctum.Games.Changes.CreateGameScheme do
  @moduledoc false

  alias Ash.Changeset

  use Ash.Resource.Change

  def change(changeset, _opts, _context) do
    case Changeset.fetch_attribute(changeset, :scenario_id) do
      {:ok, scenario_id} when is_binary(scenario_id) ->
        %{main_schemes: main_schemes} =
          Sanctum.Games.get_scenario!(scenario_id, load: [:main_schemes])

        attrs =
          Enum.map(main_schemes, fn scheme ->
            %{
              card_id: scheme.id,
              threat: scheme.base_threat,
              max_threat: scheme.max_threat,
              escalation_threat: scheme.escalation_threat,
              is_main_scheme: true
            }
          end)

        Ash.Changeset.manage_relationship(changeset, :game_schemes, attrs, type: :create)

      _ ->
        changeset
    end
  end
end
