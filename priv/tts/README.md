# Sanctum TTS importer

`sanctum_importer.lua` is the Tabletop Simulator tile script. It needs
*Marvel Champions: Hitch's Table* (Workshop 2514286571) and embeds no assets.

## Attaching it

1. Load Hitch's table.
2. Objects → Components → Blocks → Square (no image URL needed).
3. Right-click the block → Scripting → paste the file → Save & Play.
4. Paste a Sanctum deck id (or deck URL) into the input and click Import.

## Dev

Change `BASE_URL` at the top of the script to `http://localhost:4150`.

Saved Object packaging is tracked separately (#109).
