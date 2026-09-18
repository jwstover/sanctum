# Tests tagged :external hit the live MarvelCDB API and are excluded by default
# (they are non-deterministic and flake on network errors). Run them explicitly
# with `mix test --include external`.
ExUnit.start(exclude: [:external])
Ecto.Adapters.SQL.Sandbox.mode(Sanctum.Repo, :manual)

# Official aspects are reference data the `card_sides.aspect` FK points at. Seed
# them on a real (non-sandbox) connection so the rows are committed and visible
# inside every test's rolled-back sandbox transaction — otherwise any factory
# card side carrying an aspect would violate the foreign key. Idempotent.
# Official set kinds are seeded the same way so tests can read them as the
# committed reference data they are in every environment.
Ecto.Adapters.SQL.Sandbox.checkout(Sanctum.Repo, sandbox: false)
Sanctum.Release.seed_aspects()
Sanctum.Release.seed_set_kinds()
Ecto.Adapters.SQL.Sandbox.checkin(Sanctum.Repo)
