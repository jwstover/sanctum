defmodule Sanctum.Decks.WriteupTest do
  use Sanctum.DataCase, async: true

  import Sanctum.Factory

  alias Sanctum.Decks.Writeup

  describe "card link rewriting" do
    test "rewrites markdown card links to our card pages" do
      card = create(Sanctum.Games.Card, attrs: %{base_code: "41008", code: "41008"})

      html = rendered("[Training Regimen](/card/41008) tutors Skill cards.")

      assert html =~ ~s(href="/cards/#{card.id}")
      assert html =~ "Training Regimen"
      refute html =~ "marvelcdb.com"
    end

    test "rewrites raw HTML anchors pointing at marvelcdb card pages" do
      card = create(Sanctum.Games.Card, attrs: %{base_code: "41017", code: "41017"})

      html =
        rendered(~s(<a href="https://marvelcdb.com/card/41017">Float Like a Butterfly</a>))

      assert html =~ ~s(href="/cards/#{card.id}")
      assert html =~ "Float Like a Butterfly"
      refute html =~ "marvelcdb.com/card"
    end

    test "unresolved markdown links degrade to plain text" do
      html = rendered("[Mystery Card](/card/99999)")

      assert html =~ "Mystery Card"
      refute html =~ "href"
    end

    test "unresolved HTML anchors keep their marvelcdb URL" do
      html = rendered(~s(<a href="https://marvelcdb.com/card/99999">Mystery Card</a>))

      assert html =~ ~s(href="https://marvelcdb.com/card/99999")
    end

    test "non-card marvelcdb links are left alone" do
      html =
        rendered(~s(<a href="https://marvelcdb.com/find?q=surveillance">Surveillance</a>))

      assert html =~ ~s(href="https://marvelcdb.com/find?q=surveillance")
    end
  end

  defp rendered(md) do
    assert [%{kind: :inline, html: html}] = Writeup.render(md)
    html |> Phoenix.HTML.safe_to_string()
  end
end
