defmodule Sanctum.Catalog.Curated do
  @moduledoc """
  Curated release taxonomy that MarvelCDB does not expose: the wave list and,
  per pack, its `product_type` and owning `wave`.

  `apply!/0` upserts the waves, then overlays `product_type` + `wave_id` onto
  every pack that already exists (packs are synced from MarvelCDB first). It
  writes *only* those two curated columns via `Pack.set_curated`, so it never
  clobbers MarvelCDB-sourced metadata — and, being idempotent, is safe to run on
  every sync. It is a compiled module (not a `.exs`) so both `seeds.exs` and the
  sync path can call it.

  When admin editing of these fields ships, switch the overlay to
  fill-only-if-null (or stop overlaying and migrate this into the DB) so a sync
  doesn't stomp admin edits.
  """

  alias Sanctum.Catalog

  @waves for n <- 1..11, do: %{number: n, name: "Wave #{n}"}

  # Pack code => {product_type, wave number (nil for no wave)}. Only packs
  # MarvelCDB actually returns are overlaid; unknown codes are ignored.
  @packs %{
    # Wave 1 — Core Set era
    "core" => {:core, 1},
    "gob" => {:scenario_pack, 1},
    "twc" => {:scenario_pack, 1},
    "cap" => {:hero_pack, 1},
    "msm" => {:hero_pack, 1},
    "thor" => {:hero_pack, 1},
    "bkw" => {:hero_pack, 1},
    "drs" => {:hero_pack, 1},
    "hlk" => {:hero_pack, 1},
    # Wave 2 — The Rise of Red Skull
    "trors" => {:campaign_expansion, 2},
    "toafk" => {:scenario_pack, 2},
    "ant" => {:hero_pack, 2},
    "wsp" => {:hero_pack, 2},
    "qsv" => {:hero_pack, 2},
    "scw" => {:hero_pack, 2},
    # Wave 3 — The Galaxy's Most Wanted
    "gmw" => {:campaign_expansion, 3},
    "stld" => {:hero_pack, 3},
    "gam" => {:hero_pack, 3},
    "drax" => {:hero_pack, 3},
    "vnm" => {:hero_pack, 3},
    # Wave 4 — The Mad Titan's Shadow
    "mts" => {:campaign_expansion, 4},
    "nebu" => {:hero_pack, 4},
    "warm" => {:hero_pack, 4},
    "hood" => {:scenario_pack, 4},
    "valk" => {:hero_pack, 4},
    "vision" => {:hero_pack, 4},
    # Wave 5 — Sinister Motives
    "sm" => {:campaign_expansion, 5},
    "nova" => {:hero_pack, 5},
    "ironheart" => {:hero_pack, 5},
    "spiderham" => {:hero_pack, 5},
    "spdr" => {:hero_pack, 5},
    # Wave 6 — Mutant Genesis
    "mut_gen" => {:campaign_expansion, 6},
    "cyclops" => {:hero_pack, 6},
    "phoenix" => {:hero_pack, 6},
    "wolv" => {:hero_pack, 6},
    "storm" => {:hero_pack, 6},
    "mojo" => {:scenario_pack, 6},
    "gambit" => {:hero_pack, 6},
    "rogue" => {:hero_pack, 6},
    # Wave 7 — NeXt Evolution
    "next_evol" => {:campaign_expansion, 7},
    "psylocke" => {:hero_pack, 7},
    "angel" => {:hero_pack, 7},
    "x23" => {:hero_pack, 7},
    "deadpool" => {:hero_pack, 7},
    # Wave 8 — Age of Apocalypse
    "aoa" => {:campaign_expansion, 8},
    "iceman" => {:hero_pack, 8},
    "jubilee" => {:hero_pack, 8},
    "ncrawler" => {:hero_pack, 8},
    "magneto" => {:hero_pack, 8},
    # Wave 9 — Agents of S.H.I.E.L.D.
    "aos" => {:campaign_expansion, 9},
    "bp" => {:hero_pack, 9},
    "silk" => {:hero_pack, 9},
    "falcon" => {:hero_pack, 9},
    "winter" => {:hero_pack, 9},
    "tt" => {:scenario_pack, 9},
    # Wave 10 — Civil War
    "cw" => {:campaign_expansion, 10},
    "synthezoid" => {:scenario_pack, 10},
    "wonder_man" => {:hero_pack, 10},
    "hercules" => {:hero_pack, 10},
    # Wave 11 — Fear No Evil
    "fne" => {:campaign_expansion, 11},
    # No wave — standalone organized-play modular set
    "ron" => {:promo, nil}
  }

  @doc "The curated wave definitions."
  def waves, do: @waves

  @doc "Pack code => {product_type, wave_number}."
  def packs, do: @packs

  @doc """
  Upserts the waves and overlays `product_type`/`wave_id` onto every already-synced
  pack. Idempotent; system-level (`authorize?: false`).
  """
  def apply! do
    wave_ids =
      Map.new(@waves, fn attrs ->
        {:ok, wave} = Catalog.find_or_create_wave(attrs, authorize?: false)
        {attrs.number, wave.id}
      end)

    Enum.each(@packs, fn {code, {product_type, wave_number}} ->
      case Catalog.get_pack_by_code(code, authorize?: false) do
        {:ok, %Catalog.Pack{} = pack} ->
          Catalog.set_pack_curated!(
            pack,
            %{product_type: product_type, wave_id: wave_number && wave_ids[wave_number]},
            authorize?: false
          )

        # Pack not synced yet (or not in MarvelCDB) — nothing to overlay.
        _ ->
          :ok
      end
    end)

    :ok
  end
end
