defmodule Sanctum.TTS.ImporterLuaTest do
  use ExUnit.Case, async: true

  @path Path.join(File.cwd!(), "priv/tts/sanctum_importer.lua")

  test "script exists with the provenance header" do
    assert File.exists?(@path)
    src = File.read!(@path)
    assert src =~ "Written from scratch for Sanctum"
    assert src =~ "no Cerebro or Hitch Lua"
    assert src =~ "Marvel Champions: Hitch's Table"
    assert src =~ "2514286571"
  end

  test "embeds no asset URLs" do
    src = File.read!(@path)
    refute src =~ "steamusercontent"
    refute src =~ "akamaihd"
    refute src =~ ~r{https?://[^"]*\.(png|jpg)}
  end
end
