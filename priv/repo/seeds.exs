alias Sanctum.Games
alias Sanctum.MarvelCdb

:ok = MarvelCdb.load_pack("core")

Games.create_scenario!(%{name: "Rhino", set: "rhino", recommended_modular_sets: ["bomb_scare"]})
