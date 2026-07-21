%{
  configs: [
    %{
      name: "default",
      # Zero-tolerance duplication detection inside credo. NOTE: plugin params
      # override .ex_dna.exs, so keep these in sync with that file.
      plugins: [{ExDNA.Credo, [literal_mode: :abstract, normalize_pipes: true]}],
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
