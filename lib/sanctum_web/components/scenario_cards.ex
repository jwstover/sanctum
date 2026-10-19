defmodule SanctumWeb.Components.ScenarioCards do
  @moduledoc """
  Shared presentation helpers for scenarios: the villain art shown on a
  scenario's cover and the author (owner, or "Official") shown beside it.
  """

  use Phoenix.Component

  @doc """
  Primary-stage villain art for a scenario, or nil. Expects `villains:
  [:primary_side]` loaded; the lowest stage wins, ties broken by card code.
  """
  def villain_image(scenario) do
    scenario
    |> sorted_villains()
    |> Enum.find_value(fn %{primary_side: side} ->
      if is_binary(side.image_url), do: side.image_url
    end)
  end

  @doc "The scenario's lowest-stage villain card (with `primary_side` loaded), or nil."
  def primary_villain(scenario), do: scenario |> sorted_villains() |> List.first()

  @doc """
  The villain's name for display: the primary villain side's name, else the
  villain set's name when loaded, else nil.
  """
  def villain_name(scenario) do
    case primary_villain(scenario) do
      %{primary_side: %{name: name}} when is_binary(name) -> name
      _ -> villain_set_name(scenario)
    end
  end

  defp villain_set_name(%{villain_set: %{name: name}}) when is_binary(name), do: name
  defp villain_set_name(_), do: nil

  defp sorted_villains(%{villains: vs}) when is_list(vs) do
    vs
    |> Enum.filter(& &1.primary_side)
    |> Enum.sort_by(&{&1.primary_side.stage || 999, &1.code})
  end

  defp sorted_villains(_), do: []

  @doc """
  The scenario's author as `%{official?, name, avatar}`, or nil when the owner
  isn't loaded / has no username. Matches `owner_id` first so an unloaded owner
  is never read as official.
  """
  def author(%{owner_id: nil}), do: %{official?: true, name: "Official", avatar: nil}

  def author(%{owner: %{username: %Ash.CiString{} = u, avatar_url: avatar}}),
    do: %{official?: false, name: "@" <> to_string(u), avatar: avatar}

  def author(_), do: nil

  @doc "The 'Official' badge shown in place of an author."
  def official_badge(assigns) do
    ~H"""
    <span class="border-2 border-primary bg-black px-2 py-0.5 font-barlow-condensed text-xs font-bold uppercase tracking-[0.08em] text-primary">
      Official
    </span>
    """
  end
end
