# Tests tagged :external hit the live MarvelCDB API and are excluded by default
# (they are non-deterministic and flake on network errors). Run them explicitly
# with `mix test --include external`.
ExUnit.start(exclude: [:external])
Ecto.Adapters.SQL.Sandbox.mode(Sanctum.Repo, :manual)

# Official aspects are reference data the `card_sides.aspect` FK points at. Seed
# them on a real (non-sandbox) connection so the rows are committed and visible
# inside every test's rolled-back sandbox transaction — otherwise any factory
# card side carrying an aspect would violate the foreign key. Idempotent.
Ecto.Adapters.SQL.Sandbox.checkout(Sanctum.Repo, sandbox: false)
Sanctum.Release.seed_aspects()
Ecto.Adapters.SQL.Sandbox.checkin(Sanctum.Repo)
