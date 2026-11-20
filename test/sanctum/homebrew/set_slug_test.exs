defmodule Sanctum.Homebrew.SetSlugTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.HomebrewFixtures

  import Sanctum.AccountsFixtures

  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.Changes.GenerateSlug
  alias Sanctum.Homebrew.HomebrewSet

  setup do
    creator = user_fixture(%{username: "matt_murdock"})
    other = user_fixture(%{username: "foggy"})

    %{
      creator: creator,
      other: other,
      project: project_fixture(creator),
      other_project: project_fixture(other)
    }
  end

  defp project_fixture(actor),
    do: Homebrew.create_project!(%{name: "Hell's Kitchen", attestation: true}, actor: actor)

  defp set_fixture(project, actor, name),
    do: Homebrew.create_set!(%{homebrew_project_id: project.id, name: name}, actor: actor)

  defp publish!(set, actor), do: publish_set!(set, actor)

  describe "slugify/1" do
    test "folds, lowercases, hyphenates and caps names" do
      assert GenerateSlug.slugify("Daredevil") == "daredevil"
      assert GenerateSlug.slugify("  Kingpin: Café Edition! ") == "kingpin-cafe-edition"
      assert GenerateSlug.slugify("!!!") == "set"
      assert "A" |> String.duplicate(100) |> GenerateSlug.slugify() |> String.length() == 60
    end
  end

  describe "generation" do
    test "two different creators can both own the slug daredevil", ctx do
      mine = set_fixture(ctx.project, ctx.creator, "Daredevil")
      theirs = set_fixture(ctx.other_project, ctx.other, "Daredevil")

      assert mine.slug == "daredevil"
      assert theirs.slug == "daredevil"
    end

    test "the same creator's second Daredevil gets a disambiguated slug", ctx do
      first = set_fixture(ctx.project, ctx.creator, "Daredevil")
      # A different project of the same creator still counts.
      second = set_fixture(project_fixture(ctx.creator), ctx.creator, "Daredevil")
      third = set_fixture(ctx.project, ctx.creator, "daredevil!")

      assert {first.slug, second.slug, third.slug} ==
               {"daredevil", "daredevil-2", "daredevil-3"}
    end

    test "the identity rejects a duplicate (creator, slug)", ctx do
      set_fixture(ctx.project, ctx.creator, "Daredevil")
      other = set_fixture(ctx.project, ctx.creator, "Elektra")

      assert {:error, %Ash.Error.Invalid{}} =
               other
               |> Ash.Changeset.for_update(:update, %{}, authorize?: false)
               |> Ash.Changeset.force_change_attribute(:slug, "daredevil")
               |> Ash.update(authorize?: false)
    end
  end

  describe "stability" do
    test "a rename keeps the slug", ctx do
      set = ctx.project |> set_fixture(ctx.creator, "Daredevil") |> publish!(ctx.creator)
      renamed = Homebrew.update_set!(set, %{name: "The Man Without Fear"}, actor: ctx.creator)

      assert renamed.slug == "daredevil"
    end

    test "re-publishing never moves an existing slug", ctx do
      set = set_fixture(ctx.project, ctx.creator, "Daredevil")
      set = Homebrew.update_set!(set, %{name: "Elektra"}, actor: ctx.creator)
      set = publish!(set, ctx.creator)

      assert set.slug == "daredevil"
    end

    test "regenerating re-derives from the current name", ctx do
      set = set_fixture(ctx.project, ctx.creator, "Daredevil")
      set = Homebrew.update_set!(set, %{name: "Elektra"}, actor: ctx.creator)

      assert Homebrew.regenerate_set_slug!(set, actor: ctx.creator).slug == "elektra"
    end

    test "regenerating keeps a slug the name already produces", ctx do
      set_fixture(ctx.project, ctx.creator, "Daredevil")
      second = set_fixture(ctx.project, ctx.creator, "Daredevil")

      assert second.slug == "daredevil-2"
      assert Homebrew.regenerate_set_slug!(second, actor: ctx.creator).slug == "daredevil-2"
    end

    test "only the creator may regenerate", ctx do
      set = set_fixture(ctx.project, ctx.creator, "Daredevil") |> publish!(ctx.creator)

      assert {:error, %Ash.Error.Forbidden{}} =
               Homebrew.regenerate_set_slug(set, actor: ctx.other)
    end

    test "a legacy set without a slug gets one when published", ctx do
      set_fixture(ctx.project, ctx.creator, "Daredevil")
      legacy = set_fixture(ctx.project, ctx.creator, "Daredevil")

      legacy =
        legacy
        |> Ash.Changeset.for_update(:update, %{}, authorize?: false)
        |> Ash.Changeset.force_change_attribute(:slug, nil)
        |> Ash.update!(authorize?: false)

      assert legacy.slug == nil
      assert publish!(legacy, ctx.creator).slug == "daredevil-2"
    end
  end

  describe "get_set_by_creator_slug" do
    setup ctx do
      mine = ctx.project |> set_fixture(ctx.creator, "Daredevil") |> publish!(ctx.creator)
      theirs = ctx.other_project |> set_fixture(ctx.other, "Daredevil") |> publish!(ctx.other)
      %{mine: mine, theirs: theirs}
    end

    test "resolves a creator + slug pair to exactly one set", ctx do
      assert Homebrew.get_set_by_creator_slug!("matt_murdock", "daredevil").id == ctx.mine.id
      assert Homebrew.get_set_by_creator_slug!("foggy", "daredevil").id == ctx.theirs.id
      # Usernames are case-insensitive.
      assert Homebrew.get_set_by_creator_slug!("Matt_Murdock", "daredevil").id == ctx.mine.id
    end

    test "unknown username or slug is not found" do
      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.get_set_by_creator_slug("nobody", "daredevil")

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.get_set_by_creator_slug("matt_murdock", "elektra")
    end

    test "an unlisted set resolves by its link for anyone", ctx do
      unlisted =
        ctx.project
        |> set_fixture(ctx.creator, "Elektra")
        |> then(&Homebrew.set_set_visibility!(&1, :unlisted, actor: ctx.creator))

      for actor <- [nil, ctx.other, ctx.creator] do
        assert %HomebrewSet{id: id} =
                 Homebrew.get_set_by_creator_slug!("matt_murdock", "elektra", actor: actor)

        assert id == unlisted.id
      end
    end

    test "a private set resolves only for its creator", ctx do
      private = set_fixture(ctx.project, ctx.creator, "Elektra")

      for actor <- [nil, ctx.other] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Homebrew.get_set_by_creator_slug("matt_murdock", "elektra", actor: actor)
      end

      assert %HomebrewSet{id: id} =
               Homebrew.get_set_by_creator_slug!("matt_murdock", "elektra", actor: ctx.creator)

      assert id == private.id
    end
  end
end
