alias Sanctum.Games
alias Sanctum.MarvelCdb

%{status: :success} = MarvelCdb.load_pack("core")

{:ok, _modular_set} = Games.create_modular_set(%{name: "Bomb Scare", set_code: "bomb_scare"})

Games.create_scenario!(%{name: "Rhino", set: "rhino", recommended_modular_sets: ["bomb_scare"]})
