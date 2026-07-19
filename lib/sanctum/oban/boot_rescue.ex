defmodule Sanctum.Oban.BootRescue do
  @moduledoc """
  Resets Oban jobs orphaned in the `executing` state by a previous incarnation
  of **this machine** back to `available` at application boot.

  ## Why

  When a Fly machine restarts (redeploy, crash, OOM, or a `Sanctum.AutoShutdown`
  self-stop followed by autostart), any job the old node was running is abandoned
  mid-flight and left stuck in `executing`. `Oban.Plugins.Lifeline` eventually
  rescues these, but purely on a timer (`rescue_after`) — we keep that high (24h)
  so it never clobbers a genuinely long-running job, which makes it useless as a
  *fast* recovery path.

  ## Why per-machine

  The app can have more than one machine alive at once (a second Fly machine,
  autostart racing a self-stop, deploy overlap). A booting machine cannot tell
  whether another machine is mid-job, and an earlier blanket reset of *all*
  `executing` rows re-enqueued a job that was still running on the other
  machine — the same job then executed on both machines concurrently. The one
  thing a fresh boot *does* know is that nothing from its own machine survived
  the restart. So rescue is scoped to jobs whose `attempted_by` node matches
  this machine's Oban node identity.

  That identity must be stable across deploys for the match to work, so prod
  pins Oban's `:node` to `FLY_MACHINE_ID` (config/runtime.exs) — machine IDs
  survive restarts and redeploys, unlike the default BEAM node name, which
  embeds the per-deploy image ref.

  Trade-off: orphans of a machine that is destroyed and never boots again are
  not rescued here; `Oban.Plugins.Lifeline` remains the backstop for those.

  This child is placed **before** the `Oban` child in the supervision tree so the
  reset lands before any queue starts producing — otherwise it could reset a job
  the fresh node just picked up. It runs its work synchronously in `run/0` and
  returns `:ignore`, so no long-lived process remains.

  Mirrors Lifeline / Basic-engine semantics: attempts remaining → `available`;
  attempts exhausted → `discarded`.
  """

  import Ecto.Query

  require Logger

  @doc false
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :run, []},
      type: :worker,
      restart: :temporary
    }
  end

  @doc false
  def run do
    # Skipped in test: the app boots outside any Ecto sandbox ownership, so a
    # boot-time write would fail. Tests exercise `rescue_orphans/1` directly.
    # Skipped in prod_local: that env points at the production database, and a
    # local node has no business writing to prod's job table (its node identity
    # would never match a Fly machine ID anyway — this is belt and suspenders).
    if Application.get_env(:sanctum, :env) not in [:test, :prod_local] do
      rescue_orphans()
    end

    :ignore
  end

  @doc """
  Resets this node's jobs stuck in `executing` back to `available` (or
  `discarded` when their attempts are exhausted). Jobs attempted by other nodes
  are left alone — they may still be running there. Returns
  `{rescued_count, discarded_count}`.
  """
  @spec rescue_orphans(String.t()) :: {non_neg_integer(), non_neg_integer()}
  def rescue_orphans(node \\ oban_node()) do
    now = DateTime.utc_now()

    base =
      Oban.Job
      |> where([j], j.state == "executing")
      |> where([j], fragment("?[1]", j.attempted_by) == ^node)

    {rescued, _} =
      base
      |> where([j], j.attempt < j.max_attempts)
      |> Sanctum.Repo.update_all(set: [state: "available"])

    {discarded, _} =
      base
      |> where([j], j.attempt >= j.max_attempts)
      |> Sanctum.Repo.update_all(set: [state: "discarded", discarded_at: now])

    if rescued > 0 or discarded > 0 do
      Logger.info(
        "[Oban.BootRescue] reset jobs orphaned by #{node}: " <>
          "#{rescued} → available, #{discarded} → discarded"
      )
    end

    {rescued, discarded}
  end

  # The node identity Oban will run under, resolved the same way Oban does:
  # the configured `:node` (FLY_MACHINE_ID in prod) or Oban's own default.
  # Read from app env because this runs before the Oban supervisor starts.
  defp oban_node do
    :sanctum
    |> Application.fetch_env!(Oban)
    |> Keyword.get_lazy(:node, &Oban.Config.node_name/0)
  end
end
