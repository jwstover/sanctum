defmodule Sanctum.GameLog.Validations.ValidateMainSchemeChoice do
  @moduledoc """
  Requires `main_scheme_id` when the chosen scenario offers more than one main
  scheme card. Single-main-scheme scenarios get it for free from
  `Sanctum.GameLog.Changes.SetDefaultMainScheme`, so this only fires when a
  real choice existed and wasn't made.
  """
  use Ash.Resource.Validation

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def supports(_opts), do: [Ash.Changeset]

  @impl true
  def validate(changeset, _opts, _context) do
    with {:ok, scenario_id} when is_binary(scenario_id) <-
           Ash.Changeset.fetch_attribute(changeset, :scenario_id),
         scenario <- Sanctum.Games.get_scenario!(scenario_id, load: [:main_schemes]),
         true <- length(scenario.main_schemes) > 1,
         nil <- Ash.Changeset.get_attribute(changeset, :main_scheme_id) do
      {:error,
       field: :main_scheme_id,
       message: "this scenario offers more than one main scheme — choose which one was used"}
    else
      _ -> :ok
    end
  end
end
