%{
  configs: [
    %{
      name: "default",
      checks: [
        {Credo.Check.Design.TagTODO, priority: :low},
        {Credo.Check.Readability.ModuleDoc, priority: :low},
        {Credo.Check.Refactor.CyclomaticComplexity, false},
        # Duplication is scanned by ex_dna (`mix ex_dna`, config in .ex_dna.exs)
        # as a separate zero-tolerance ck/CI step; this built-in check is
        # superseded by it (ex_dna also catches renamed-variable clones).
        {Credo.Check.Design.DuplicatedCode, false}
      ]
      # files etc.
    }
  ]
}
