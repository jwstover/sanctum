%{
  configs: [
    %{
      name: "default",
      checks: [
        {Credo.Check.Design.TagTODO, priority: :low},
        {Credo.Check.Readability.ModuleDoc, priority: :low},
      ],
      # files etc.
    }
  ]
}
