defmodule Sanctum.Oban.BootRescueTest do
  use Sanctum.DataCase, async: true

  alias Sanctum.Oban.BootRescue

  defp insert_job(attrs) do
    defaults = %{worker: "Sanctum.FakeWorker", queue: "default", args: %{}, max_attempts: 3}

    %Oban.Job{}
    |> Ecto.Changeset.change(Map.merge(defaults, attrs))
    |> Repo.insert!()
  end

  defp reload(job), do: Repo.get!(Oban.Job, job.id)

  test "moves an orphaned executing job with attempts remaining back to available" do
    job = insert_job(%{state: "executing", attempt: 1, attempted_at: DateTime.utc_now()})

    assert {1, 0} = BootRescue.rescue_orphans()
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

    assert {0, 1} = BootRescue.rescue_orphans()

    reloaded = reload(job)
    assert reloaded.state == "discarded"
    assert reloaded.discarded_at
  end

  test "leaves jobs in non-executing states untouched" do
    available = insert_job(%{state: "available"})
    scheduled = insert_job(%{state: "scheduled", scheduled_at: DateTime.utc_now()})
    completed = insert_job(%{state: "completed", completed_at: DateTime.utc_now()})

    assert {0, 0} = BootRescue.rescue_orphans()

    assert reload(available).state == "available"
    assert reload(scheduled).state == "scheduled"
    assert reload(completed).state == "completed"
  end

  test "returns zero counts when nothing is executing" do
    assert {0, 0} = BootRescue.rescue_orphans()
  end
end
