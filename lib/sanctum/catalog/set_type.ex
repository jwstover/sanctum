defmodule Sanctum.Catalog.SetType do
  @moduledoc """
  The game role of a `CardSet`, mapped from MarvelCDB's
  `card_set_type_name_code`.

  Kept faithful rather than collapsed — these distinctions (Standard vs Expert
  encounter sets, nemesis vs modular, etc.) are real game roles. MarvelCDB's
  `hero_special` folds into `:hero`; a `null` card set produces no `CardSet`.
  """

  use Ash.Type.Enum,
    values: [
      :hero,
      :villain,
      :nemesis,
      :modular,
      :main_scheme,
      :standard,
      :expert,
      :leader,
      :evidence
    ]
end
