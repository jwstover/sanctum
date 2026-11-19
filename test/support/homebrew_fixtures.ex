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

  @doc """
  Publishes `set` as `actor` through `:set_visibility`, clearing both publish
  gates: the set's creator gets a username if they have none, and the first
  publish attests.
  """
  def publish_set!(%Homebrew.HomebrewSet{} = set, actor) do
    ensure_username!(set.creator_id)
    Homebrew.set_set_visibility!(set, :published, %{attest: true}, actor: actor)
  end

  defp ensure_username!(creator_id) do
    case Ash.get!(Sanctum.Accounts.User, creator_id, authorize?: false) do
      %{username: nil} = user ->
        user
        |> Ash.Changeset.for_update(:update_profile, %{
          username: "creator_#{System.unique_integer([:positive])}"
        })
        |> Ash.update!(authorize?: false)

      user ->
        user
    end
  end
end
