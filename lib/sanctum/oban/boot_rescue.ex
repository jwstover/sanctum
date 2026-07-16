defmodule Sanctum.Oban.BootRescue do
  @moduledoc """
  Resets Oban jobs orphaned in the `executing` state by a previous, now-dead
  node back to `available` at application boot.

  ## Why

  When a Fly machine restarts (redeploy, crash, OOM, or a `Sanctum.AutoShutdown`
  self-stop followed by autostart), any job the old node was running is abandoned
  mid-flight and left stuck in `executing`. `Oban.Plugins.Lifeline` eventually
  rescues these, but purely on a timer (`rescue_after`) — we keep that high (24h)
  so it never clobbers a genuinely long-running job, which makes it useless as a
  *fast* recovery path.

  Sanctum runs a **single** Oban node (Fly scale-to-zero: `auto_stop_machines =
  "off"`, one machine, self-stop when idle). That makes recovery trivial: on
  boot, nothing else can possibly be running a job, so *every* `executing` row is
  a corpse from the prior boot and is safe to reset immediately — no
  node/producer matching required. (Node names embed the image ref and private IP
  and change across deploys anyway, so matching would be unreliable.)

  This child is placed **before** the `Oban` child in the supervision tree so the
  reset lands before any queue starts producing — otherwise it could reset a job
  the fresh node just picked up. It runs its work synchronously in `run/0` and
  returns `:ignore`, so no long-lived process remains.

  Mirrors Lifeline / Basic-engine semantics: attempts remaining → `available`;
  attempts exhausted → `discarded`.

  > #### Single-node assumption {: .warning}
  >
  > This blanket reset is only safe because there is exactly one live Oban node.
  > If Sanctum ever runs multiple Oban nodes, replace this with producer-aware
  > rescuing (Oban Pro's `DynamicLifeline`) or it will clobber peers' live jobs.
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
    # boot-time write would fail. Tests exercise `rescue_orphans/0` directly.
    if Application.get_env(:sanctum, :env) != :test do
      rescue_orphans()
    end

    :ignore
  end

  @doc """
  Resets every job stuck in `executing` back to `available` (or `discarded` when
  its attempts are exhausted). Returns `{rescued_count, discarded_count}`.
  """
  @spec rescue_orphans() :: {non_neg_integer(), non_neg_integer()}
  def rescue_orphans do
    now = DateTime.utc_now()
    base = where(Oban.Job, [j], j.state == "executing")

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
        "[Oban.BootRescue] reset orphaned executing jobs: " <>
          "#{rescued} → available, #{discarded} → discarded"
      )
    end

    {rescued, discarded}
  end
end
