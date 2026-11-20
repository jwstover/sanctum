defmodule Sanctum.Homebrew.SetReportTest do
  @moduledoc false

  use Sanctum.DataCase, async: true

  import Sanctum.AccountsFixtures
  import Sanctum.HomebrewFixtures

  alias Sanctum.Homebrew
  alias Sanctum.Homebrew.HomebrewSet

  setup do
    creator = user_fixture()

    project =
      Homebrew.create_project!(%{name: "Hell's Kitchen", attestation: true}, actor: creator)

    set =
      Homebrew.create_set!(%{homebrew_project_id: project.id, name: "Kingpin"}, actor: creator)

    %{
      creator: creator,
      reporter: user_fixture(),
      admin: admin_user_fixture(),
      project: project,
      set: set
    }
  end

  defp report!(set, reporter, attrs \\ %{}) do
    Homebrew.report_set!(
      Map.merge(%{homebrew_set_id: set.id, reason: :copyright, details: "Scanned art"}, attrs),
      actor: reporter
    )
  end

  defp reload!(set), do: Ash.get!(HomebrewSet, set.id, authorize?: false)

  describe "reporting" do
    test "a signed-in user can report a published set", ctx do
      set = publish_set!(ctx.set, ctx.creator)
      report = report!(set, ctx.reporter)

      assert report.status == :open
      assert report.reporter_id == ctx.reporter.id
      assert report.reason == :copyright
    end

    test "an unlisted set can be reported through its link", ctx do
      publish_set!(ctx.set, ctx.creator)
      set = Homebrew.set_set_visibility!(ctx.set, :unlisted, actor: ctx.creator)
      assert %{status: :open} = report!(set, ctx.reporter)
    end

    test "a private set can't be reported", ctx do
      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.report_set(%{homebrew_set_id: ctx.set.id, reason: :spam},
                 actor: ctx.reporter
               )
    end

    test "anonymous visitors can't report", ctx do
      set = publish_set!(ctx.set, ctx.creator)

      assert {:error, _} =
               Homebrew.report_set(%{homebrew_set_id: set.id, reason: :spam}, actor: nil)

      assert Ash.read!(Homebrew.SetReport, authorize?: false) == []
    end

    test "a user reports a given set once", ctx do
      set = publish_set!(ctx.set, ctx.creator)
      report!(set, ctx.reporter)

      assert {:error, %Ash.Error.Invalid{}} =
               Homebrew.report_set(%{homebrew_set_id: set.id, reason: :spam},
                 actor: ctx.reporter
               )
    end
  end

  describe "the admin queue" do
    test "admins see open reports; nobody else does", ctx do
      set = publish_set!(ctx.set, ctx.creator)
      report = report!(set, ctx.reporter)

      assert [%{id: id}] = Homebrew.list_open_set_reports!(actor: ctx.admin)
      assert id == report.id

      # Reads filter rather than raise: non-admins just see nothing.
      assert Homebrew.list_open_set_reports!(actor: ctx.reporter) == []
      assert Homebrew.list_open_set_reports!(actor: ctx.creator) == []
    end

    test "an admin can dismiss a report", ctx do
      set = publish_set!(ctx.set, ctx.creator)
      report = report!(set, ctx.reporter)

      dismissed = Homebrew.dismiss_set_report!(report, actor: ctx.admin)
      assert dismissed.status == :dismissed
      assert dismissed.resolved_by_id == ctx.admin.id
      assert dismissed.resolved_at
      assert Homebrew.list_open_set_reports!(actor: ctx.admin) == []
      # The set is untouched.
      assert reload!(set).visibility == :published
    end

    test "non-admins can't dismiss", ctx do
      set = publish_set!(ctx.set, ctx.creator)
      report = report!(set, ctx.reporter)

      assert {:error, %Ash.Error.Forbidden{}} =
               Homebrew.dismiss_set_report(report, actor: ctx.creator)
    end
  end

  describe "takedown" do
    test "an admin unpublishes a set without deleting it and actions its reports", ctx do
      set = publish_set!(ctx.set, ctx.creator)
      report!(set, ctx.reporter)
      report!(set, user_fixture(), %{reason: :offensive})

      taken = Homebrew.take_down_set!(set, actor: ctx.admin)

      assert taken.visibility == :private
      assert taken.taken_down_at
      assert reload!(set).id == set.id
      assert Homebrew.list_open_set_reports!(actor: ctx.admin) == []

      statuses =
        Homebrew.SetReport
        |> Ash.read!(authorize?: false)
        |> Enum.map(&{&1.status, &1.resolved_by_id})

      assert statuses == [{:actioned, ctx.admin.id}, {:actioned, ctx.admin.id}]

      # Gone from the public directory, still in the creator's workspace.
      refute Enum.any?(Homebrew.list_directory_sets!(actor: nil), &(&1.id == set.id))
      assert Homebrew.get_set!(set.id, actor: ctx.creator)
      assert [%{id: id}] = Homebrew.list_taken_down_sets!(actor: ctx.admin)
      assert id == set.id
    end

    test "the creator can't republish a taken-down set until an admin restores it", ctx do
      set = publish_set!(ctx.set, ctx.creator)
      taken = Homebrew.take_down_set!(set, actor: ctx.admin)

      for visibility <- [:published, :unlisted] do
        assert {:error, %Ash.Error.Invalid{}} =
                 Homebrew.set_set_visibility(taken, visibility, actor: ctx.creator)
      end

      restored = Homebrew.restore_set!(taken, actor: ctx.admin)
      assert restored.taken_down_at == nil
      assert restored.visibility == :private

      assert %{visibility: :published} =
               Homebrew.set_set_visibility!(restored, :published, actor: ctx.creator)
    end

    test "creators and other users can't take down, restore or see takedowns", ctx do
      set = publish_set!(ctx.set, ctx.creator)

      for actor <- [ctx.creator, ctx.reporter] do
        assert {:error, %Ash.Error.Forbidden{}} = Homebrew.take_down_set(set, actor: actor)
      end

      taken = Homebrew.take_down_set!(set, actor: ctx.admin)

      assert {:error, %Ash.Error.Forbidden{}} = Homebrew.restore_set(taken, actor: ctx.creator)
      assert Homebrew.list_taken_down_sets!(actor: ctx.creator) == []
    end
  end
end
