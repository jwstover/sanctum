%{
  configs: [
    %{
      name: "default",
      checks: [
        {Credo.Check.Design.TagTODO, priority: :low},
        {Credo.Check.Readability.ModuleDoc, priority: :low},
        {Credo.Check.Refactor.CyclomaticComplexity, false},
        # Duplication is scanned by ex_dna (`mix ex_dna`, config in .ex_dna.exs)
        # as a separate ck/CI step with a --max-clones ratchet; once the ratchet
        # reaches 0 this can move to the tighter ExDNA.Credo plugin instead.
        {Credo.Check.Design.DuplicatedCode, false}
      ]
      # files etc.
    }
  ]
}
