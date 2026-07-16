defmodule Sanctum.Oban.BootRescueTest do
  use Sanctum.DataCase, async: true

  alias Sanctum.Oban.BootRescue

  @node "machine-self"
  @other_node "machine-other"

  defp insert_job(attrs) do
    defaults = %{
      worker: "Sanctum.FakeWorker",
      queue: "default",
      args: %{},
      max_attempts: 3,
      attempted_by: [@node, Ecto.UUID.generate()]
    }

    %Oban.Job{}
    |> Ecto.Changeset.change(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp reload(job), do: Repo.get!(Oban.Job, job.id)

  test "moves an orphaned executing job with attempts remaining back to available" do
    job = insert_job(%{state: "executing", attempt: 1, attempted_at: DateTime.utc_now()})

    assert {1, 0} = BootRescue.rescue_orphans(@node)
    assert reload(job).state == "available"
  end

  test "discards an orphaned executing job that has exhausted its attempts" do
    job =
      insert_job(%{
        state: "executing",
        attempt: 3,
        max_attempts: 3,
        attempted_at: DateTime.utc_now()
      })

    assert {0, 1} = BootRescue.rescue_orphans(@node)

    reloaded = reload(job)
    assert reloaded.state == "discarded"
    assert reloaded.discarded_at
  end

  test "leaves executing jobs attempted by other nodes untouched" do
    foreign =
      insert_job(%{
        state: "executing",
        attempt: 1,
        attempted_at: DateTime.utc_now(),
        attempted_by: [@other_node, Ecto.UUID.generate()]
      })

    assert {0, 0} = BootRescue.rescue_orphans(@node)
    assert reload(foreign).state == "executing"
  end

  test "leaves jobs in non-executing states untouched" do
    available = insert_job(%{state: "available", attempted_by: nil})
    scheduled = insert_job(%{state: "scheduled", scheduled_at: DateTime.utc_now()})
    completed = insert_job(%{state: "completed", completed_at: DateTime.utc_now()})

    assert {0, 0} = BootRescue.rescue_orphans(@node)

    assert reload(available).state == "available"
    assert reload(scheduled).state == "scheduled"
    assert reload(completed).state == "completed"
  end

  test "returns zero counts when nothing is executing" do
    assert {0, 0} = BootRescue.rescue_orphans(@node)
  end

  test "defaults to the node identity Oban will run under" do
    # No :node is configured in test, so resolution falls through to Oban's
    # own default — the same value a real Oban instance here would stamp
    # into attempted_by.
    default_node = Oban.Config.node_name()

    job =
      insert_job(%{
        state: "executing",
        attempt: 1,
        attempted_at: DateTime.utc_now(),
        attempted_by: [default_node, Ecto.UUID.generate()]
      })

    assert {1, 0} = BootRescue.rescue_orphans()
    assert reload(job).state == "available"
  end
end
