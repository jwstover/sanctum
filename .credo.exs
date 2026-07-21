%{
  configs: [
    %{
      name: "default",
      # Surfaces duplication findings inside credo; display-only
      # (exit_status: 0) — enforcement is the ratcheted `mix ex_dna` ck/CI
      # step. NOTE: plugin params override .ex_dna.exs; keep them in sync.
      plugins: [
        {ExDNA.Credo, [literal_mode: :abstract, normalize_pipes: true, exit_status: 0]}
      ],
      checks: [
        {Credo.Check.Design.TagTODO, priority: :low},
        {Credo.Check.Readability.ModuleDoc, priority: :low},
        {Credo.Check.Refactor.CyclomaticComplexity, false},
        # Superseded by the ExDNA.Credo plugin above (also catches
        # renamed-variable clones); `mix ex_dna` prints the detailed report.
        {Credo.Check.Design.DuplicatedCode, false}
      ]
      # files etc.
    }
  ]
}
