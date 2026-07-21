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
      assert project.visibility == :private
      assert project.maturity == :draft
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

    test "unlisted projects stay creator-only for now", ctx do
      Homebrew.set_project_visibility!(ctx.project, :unlisted, actor: ctx.creator)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.get_project(ctx.project.id, actor: ctx.other)
    end

    test "published projects are visible to everyone", ctx do
      Homebrew.set_project_visibility!(ctx.project, :published, actor: ctx.creator)

      assert {:ok, _} = Homebrew.get_project(ctx.project.id, actor: ctx.other)
      assert {:ok, _} = Homebrew.get_project(ctx.project.id)
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
            homebrew_project_id: ctx.project.id,
            card_sides: [%{image_url: "https://img.test/a.png"}]
          },
          ctx.creator
        )

      :ok = Homebrew.destroy_project(ctx.project, actor: ctx.creator)

      assert {:error, _} = Ash.get(Sanctum.Games.Card, card.id, authorize?: false)
    end
  end

  test "project visibility enum rejects unknown values" do
    user = user_fixture()
    project = project_fixture(user)

    assert {:error, _} = Homebrew.set_project_visibility(project, :secret, actor: user)
  end

  test "resource is registered with a card_count aggregate" do
    user = user_fixture()
    project = project_fixture(user)

    assert %HomebrewProject{card_count: 0} =
             Homebrew.get_project!(project.id, actor: user, load: [:card_count])
  end
end
