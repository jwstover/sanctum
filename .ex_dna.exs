# ex_dna duplication-detection config (https://hex.pm/packages/ex_dna).
# Run with `mix ex_dna`; `mix ck` and CI enforce a --max-clones ratchet —
# lower that number as existing clones are cleaned up, never raise it.
%{
  # Also catch renamed-variable clones (Type II), not just verbatim copies —
  # rewritten-but-identical functions are the most common duplication pattern.
  literal_mode: :abstract,
  # Treat `x |> f()` and `f(x)` as the same code.
  normalize_pipes: true
}
