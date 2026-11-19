defmodule Sanctum.HomebrewFixtures do
  @moduledoc """
  Test helpers for homebrew content.
  """

  alias Sanctum.Homebrew

  @doc """
  The project's oldest set, created (named after the project) when it has none.
  Calling it again returns the same set, so tests can use it as "the" set.
  """
  def project_set_fixture(%Homebrew.HomebrewProject{} = project, actor) do
    case Homebrew.list_project_sets!(project.id, actor: actor) do
      [] ->
        Homebrew.create_set!(%{homebrew_project_id: project.id, name: project.name}, actor: actor)

      sets ->
        Enum.min_by(sets, & &1.inserted_at, DateTime)
    end
  end
end
