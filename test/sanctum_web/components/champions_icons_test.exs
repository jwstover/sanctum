defmodule SanctumWeb.Components.ChampionsIconsTest do
  use ExUnit.Case, async: true

  alias SanctumWeb.Components.ChampionsIcons

  describe "resource_color/1" do
    # Sanctum.CardText.icon_span/1 emits `text-res-<token>` at runtime, but
    # only the literal class names in ChampionsIcons' @resource_colors keep
    # those utilities in the compiled CSS (CardText is outside Tailwind's
    # @source scan path). This pins the two to the same naming convention so
    # a rename in either place can't silently ship colorless icons again.
    test "matches the class names CardText emits for every resource token" do
      for token <- ~w(energy mental physical wild) do
        assert ChampionsIcons.resource_color(token) == "text-res-#{token}"

        assert Sanctum.CardText.icon_span(token) ==
                 ~s(<span class="font-champions leading-none text-res-#{token}">) <>
                   Map.fetch!(Sanctum.CardText.icons(), token) <> "</span>"
      end
    end

    test "returns nil for non-resource tokens" do
      assert ChampionsIcons.resource_color("boost") == nil
      assert ChampionsIcons.resource_color(:cost) == nil
    end
  end
end
