defmodule Sanctum.CardTextTest do
  use ExUnit.Case, async: true

  import Phoenix.HTML, only: [safe_to_string: 1]

  alias Sanctum.CardText

  defp render(text), do: text |> CardText.to_html() |> safe_to_string()

  describe "to_html/1" do
    test "returns empty safe value for nil and empty string" do
      assert CardText.to_html(nil) == {:safe, []}
      assert CardText.to_html("") == {:safe, []}
    end

    test "passes through whitelisted emphasis tags" do
      assert render("<b>Interrupt</b>: draw a card") ==
               "<b>Interrupt</b>: draw a card"

      assert render("<i>quiet</i> and <em>loud</em>") ==
               "<i>quiet</i> and <em>loud</em>"
    end

    test "escapes stray HTML and ampersands so nothing is injected" do
      assert render(~s(1 < 2 & "three" <script>x</script>)) ==
               "1 &lt; 2 &amp; &quot;three&quot; &lt;script&gt;x&lt;/script&gt;"
    end

    test "converts newlines to <br>" do
      assert render("line one\nline two") == "line one<br>line two"
      assert render("a\r\nb") == "a<br>b"
    end

    test "renders resource tokens as colored ChampionsIcons glyphs" do
      assert render("[energy]") ==
               ~s(<span class="font-champions leading-none text-res-energy">E</span>)

      assert render("[physical]") ==
               ~s(<span class="font-champions leading-none text-res-physical">P</span>)
    end

    test "renders non-resource tokens as uncolored glyphs" do
      assert render("[star]") ==
               ~s(<span class="font-champions leading-none">S</span>)

      assert render("[per_hero]") ==
               ~s(<span class="font-champions leading-none">G</span>)
    end

    test "falls back to small-caps name for tokens without a glyph" do
      assert render("[attack]") ==
               ~s(<span class="font-semibold uppercase tracking-wide">attack</span>)

      assert render("[per_group_missing]") =~ "per group missing"
      refute render("[guardian]") =~ "["
    end

    test "renders <hr /> dividers and drops stray empty emphasis tags" do
      assert render("above\n<hr />\nbelow") ==
               ~s(above<br><hr class="my-2 border-neutral/60"><br>below)

      assert render("a<b/>b") == "ab"
    end

    test "renders [[Trait]] double-bracket references in the Komika face" do
      assert render("[[X-MEN]]") == ~s(<span class="font-komika">X-MEN</span>)

      assert render("[[S.H.I.E.L.D.]] and [[Board Member]]") ==
               ~s(<span class="font-komika">S.H.I.E.L.D.</span> and ) <>
                 ~s(<span class="font-komika">Board Member</span>)
    end

    test "does not confuse a [[Trait]] with single-bracket icon tokens" do
      html = render("[[Attack]] then [attack]")

      assert html ==
               ~s(<span class="font-komika">Attack</span> then ) <>
                 ~s(<span class="font-semibold uppercase tracking-wide">attack</span>)
    end

    test "handles a realistic mixed line" do
      html = render("<b>Forced Response</b>: discard the top card.\n[physical] - Deal 2 damage.")

      assert html ==
               "<b>Forced Response</b>: discard the top card.<br>" <>
                 ~s(<span class="font-champions leading-none text-res-physical">P</span>) <>
                 " - Deal 2 damage."
    end
  end
end
