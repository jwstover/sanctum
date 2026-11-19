defmodule Sanctum.Homebrew.HomebrewProjectTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures

  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.HomebrewProject

  defp project_fixture(actor, attrs \\ %{}) do
    Homebrew.create_project!(
      Map.merge(%{name: "Test Project", attestation: true}, attrs),
      actor: actor
    )
  end

  describe "create" do
    test "relates the actor as creator and applies defaults" do
      user = user_fixture()

      project = project_fixture(user)

      assert project.creator_id == user.id
      assert project.attestation
    end

    test "requires the attestation" do
      user = user_fixture()

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.create_project(%{name: "No Attestation"}, actor: user)
    end

    test "requires an actor" do
      assert {:error, _} = Homebrew.create_project(%{name: "Ghost", attestation: true})
    end
  end

  describe "read visibility" do
    setup do
      creator = user_fixture()
      %{creator: creator, other: user_fixture(), project: project_fixture(creator)}
    end

    test "private projects are invisible to everyone but the creator", ctx do
      assert {:ok, _} = Homebrew.get_project(ctx.project.id, actor: ctx.creator)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.get_project(ctx.project.id, actor: ctx.other)

      assert {:error, %Ash.Error.Invalid{}} = Homebrew.get_project(ctx.project.id)
    end

    test "publishing a set does not expose its project (privacy follows the set)", ctx do
      ctx.project
      |> Homebrew.ensure_project_set(ctx.creator)
      |> Homebrew.set_set_visibility!(:published, actor: ctx.creator)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.get_project(ctx.project.id, actor: ctx.other)

      assert {:error, %Ash.Error.Invalid{}} = Homebrew.get_project(ctx.project.id)
    end

    test "admins see everything", ctx do
      assert {:ok, _} = Homebrew.get_project(ctx.project.id, actor: admin_user_fixture())
    end

    test "for_creator lists only the actor's projects", ctx do
      project_fixture(ctx.other, %{name: "Someone Else's"})

      assert [project] = Homebrew.list_my_projects!(actor: ctx.creator)
      assert project.id == ctx.project.id
    end
  end

  describe "update / destroy" do
    setup do
      creator = user_fixture()
      %{creator: creator, other: user_fixture(), project: project_fixture(creator)}
    end

    test "creator can update; others cannot even see it", ctx do
      assert {:ok, updated} =
               Homebrew.update_project(ctx.project, %{name: "Renamed"}, actor: ctx.creator)

      assert updated.name == "Renamed"

      assert {:error, _} =
               Homebrew.update_project(ctx.project, %{name: "Hijacked"}, actor: ctx.other)
    end

    test "creator can destroy; others cannot", ctx do
      assert {:error, _} = Homebrew.destroy_project(ctx.project, actor: ctx.other)
      assert :ok = Homebrew.destroy_project(ctx.project, actor: ctx.creator)
      assert {:error, _} = Homebrew.get_project(ctx.project.id, actor: ctx.creator)
    end

    test "destroying a project takes its custom cards with it", ctx do
      {:ok, card} =
        Homebrew.create_custom_card(
          %{
            homebrew_set_id: Homebrew.ensure_project_set(ctx.project, ctx.creator).id,
            card_sides: [%{image_url: "https://img.test/a.png"}]
          },
          ctx.creator
        )

      :ok = Homebrew.destroy_project(ctx.project, actor: ctx.creator)

      assert {:error, _} = Ash.get(Sanctum.Games.Card, card.id, authorize?: false)
    end
  end

  test "a project carries no outward-facing fields — those live on the set" do
    for field <- [:visibility, :maturity, :tags, :banner_url, :content_types] do
      refute Ash.Resource.Info.attribute(HomebrewProject, field)
    end
  end

  test "card_count counts custom cards across the project's sets" do
    user = user_fixture()
    project = project_fixture(user)

    assert %HomebrewProject{card_count: 0} =
             Homebrew.get_project!(project.id, actor: user, load: [:card_count])

    for _ <- 1..2 do
      set = Homebrew.create_set!(%{name: "Set", homebrew_project_id: project.id}, actor: user)

      {:ok, _card} =
        Homebrew.create_custom_card(
          %{homebrew_set_id: set.id, card_sides: [%{image_url: "https://img.test/a.png"}]},
          user
        )
    end

    assert %HomebrewProject{card_count: 2} =
             Homebrew.get_project!(project.id, actor: user, load: [:card_count])
  end
end
