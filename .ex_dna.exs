# ex_dna duplication-detection config (https://hex.pm/packages/ex_dna).
# `mix ck` and CI run `mix ex_dna` with zero tolerance — any detected clone
# fails the build; extract the shared logic instead of duplicating it.
%{
  # Also catch renamed-variable clones (Type II), not just verbatim copies —
  # rewritten-but-identical functions are the most common duplication pattern.
  literal_mode: :abstract,
  # Treat `x |> f()` and `f(x)` as the same code.
  normalize_pipes: true
}
