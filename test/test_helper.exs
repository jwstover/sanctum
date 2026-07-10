# Tests tagged :external hit the live MarvelCDB API and are excluded by default
# (they are non-deterministic and flake on network errors). Run them explicitly
# with `mix test --include external`.
ExUnit.start(exclude: [:external])
Ecto.Adapters.SQL.Sandbox.mode(Sanctum.Repo, :manual)
