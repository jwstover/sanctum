alias Sanctum.Games
alias Sanctum.MarvelCdb

# Seeds only the core set with marvelcdb-hosted image URLs; run
# `mix sanctum.sync_cards` to load everything and point images at the bucket.
:ok = MarvelCdb.load_pack("core")

{:ok, _modular_set} = Games.create_modular_set(%{name: "Bomb Scare", set_code: "bomb_scare"})

Games.create_scenario!(%{name: "Rhino", set: "rhino", recommended_modular_sets: ["bomb_scare"]})
