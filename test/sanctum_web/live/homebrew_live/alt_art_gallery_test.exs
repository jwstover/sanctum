defmodule SanctumWeb.HomebrewLive.AltArtGalleryTest do
  @moduledoc false

  use SanctumWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Sanctum.Factory
  import Sanctum.HomebrewFixtures

  alias Sanctum.Games
  alias Sanctum.Games.Card
  alias Sanctum.Games.CardSide
  alias Sanctum.Heroes.Hero
  alias Sanctum.Homebrew

  setup do
    # A hero set (identity + signature card) and an aspect card with no set.
    identity = official_card!("91001", "spidey_test", "Spider-Man", :hero)
    web_shooter = official_card!("91002", "spidey_test", "Web-Shooter", :upgrade)
    hulk_ally = official_card!("91003", nil, "Hulk", :ally)

    Hero
    |> Ash.Changeset.for_create(:create, %{
      hero_name: "Spider-Man",
      alter_ego_name: "Peter Parker",
      set: "spidey_test",
      card_id: identity.id
    })
    |> Ash.create!(authorize?: false)

    matt = user_fixture(%{username: "matt_murdock"})
    jess = user_fixture(%{username: "jessica_jones"})

    matt_set = published_set!(matt, "Hell's Kitchen Art")
    jess_set = published_set!(jess, "Alias Art")

    private_set =
      Homebrew.create_set!(
        %{homebrew_project_id: matt_set.homebrew_project_id, name: "Drafts"},
        actor: matt
      )

    spidey_alt = alt!(matt, matt_set, identity, "Ditko Fan", "spidey.png")
    shooter_alt = alt!(jess, jess_set, web_shooter, "Romita Fan", "shooter.png")
    hulk_alt = alt!(jess, jess_set, hulk_ally, "Ditko Fan", "hulk.png")
    private_alt = alt!(matt, private_set, identity, "Secret Artist", "secret.png")

    %{
      matt: matt,
      matt_set: matt_set,
      identity: identity,
      web_shooter: web_shooter,
      spidey_alt: spidey_alt,
      shooter_alt: shooter_alt,
      hulk_alt: hulk_alt,
      private_alt: private_alt
    }
  end

  defp official_card!(code, set, name, type) do
    card = create(Card, attrs: %{code: code, base_code: code, set: set})

    create(CardSide,
      attrs: %{
        card_id: card.id,
        name: name,
        code: code <> "a",
        side_identifier: "a",
        is_primary_side: true,
        type: type
      }
    )

    card
  end

  defp published_set!(user, name) do
    project = Homebrew.create_project!(%{name: name, attestation: true}, actor: user)

    project
    |> project_set_fixture(user)
    |> publish_set!(user)
  end

  defp alt!(user, set, card, artist, filename) do
    Games.create_custom_alt!(
      %{
        homebrew_set_id: set.id,
        image_url: "https://img.test/#{filename}",
        target_card_id: card.id,
        artist: artist
      },
      actor: user
    )
  end

  test "anonymous visitors see only alts in published sets", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom/alt-art")

    assert has_element?(lv, "#fan-content-notice")
    assert has_element?(lv, "#gallery-alt-#{ctx.spidey_alt.id}")
    assert has_element?(lv, "#gallery-alt-#{ctx.shooter_alt.id}")
    assert has_element?(lv, "#gallery-alt-#{ctx.hulk_alt.id}")
    refute has_element?(lv, "#gallery-alt-#{ctx.private_alt.id}")
    assert has_element?(lv, "#gallery-count", "3")
  end

  test "the creator doesn't see their own private alts in the gallery", ctx do
    {:ok, lv, _html} = live(log_in_user(ctx.conn, ctx.matt), ~p"/custom/alt-art")

    refute has_element?(lv, "#gallery-alt-#{ctx.private_alt.id}")
    refute has_element?(lv, "#filter-artist option", "Secret Artist")
  end

  test "groups by depicted character: hero set, else the card's own name", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom/alt-art")

    # Both hero-set cards (identity and signature card) group under the hero.
    assert has_element?(lv, "#group-1 .group-name", "Spider-Man")
    assert has_element?(lv, "#group-1 #gallery-alt-#{ctx.spidey_alt.id}")
    assert has_element?(lv, "#group-1 #gallery-alt-#{ctx.shooter_alt.id}")

    # A set-less aspect ally groups under its own name.
    assert has_element?(lv, "#group-0 .group-name", "Hulk")
    assert has_element?(lv, "#group-0 #gallery-alt-#{ctx.hulk_alt.id}")
  end

  test "tiles link to the official card and to the owning set", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom/alt-art")

    tile = "#gallery-alt-#{ctx.spidey_alt.id}"
    assert has_element?(lv, "#{tile} a.alt-card-name[href='/cards/#{ctx.identity.id}']")

    assert has_element?(
             lv,
             "#{tile} a.alt-set-link[href='/custom/@matt_murdock/#{ctx.matt_set.slug}']",
             "Hell's Kitchen Art"
           )

    assert has_element?(lv, "#{tile} .alt-artist", "Ditko Fan")
    assert has_element?(lv, "#{tile} .alt-creator", "@matt_murdock")
  end

  test "the artist filter narrows through the URL", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom/alt-art")

    lv |> form("#gallery-filters", %{artist: "Ditko Fan"}) |> render_change()
    assert_patch(lv, ~p"/custom/alt-art?#{%{artist: "Ditko Fan"}}")

    assert has_element?(lv, "#gallery-alt-#{ctx.spidey_alt.id}")
    assert has_element?(lv, "#gallery-alt-#{ctx.hulk_alt.id}")
    refute has_element?(lv, "#gallery-alt-#{ctx.shooter_alt.id}")
  end

  test "the creator filter narrows", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom/alt-art?creator=jessica_jones")

    assert has_element?(lv, "#gallery-alt-#{ctx.shooter_alt.id}")
    assert has_element?(lv, "#gallery-alt-#{ctx.hulk_alt.id}")
    refute has_element?(lv, "#gallery-alt-#{ctx.spidey_alt.id}")
  end

  test "the target-card filter narrows and combines with others", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom/alt-art?card=#{ctx.web_shooter.id}")

    assert has_element?(lv, "#gallery-alt-#{ctx.shooter_alt.id}")
    refute has_element?(lv, "#gallery-alt-#{ctx.spidey_alt.id}")
    refute has_element?(lv, "#gallery-alt-#{ctx.hulk_alt.id}")
    assert has_element?(lv, "#filter-card option", "Web-Shooter (91002)")

    {:ok, lv, _html} =
      live(ctx.conn, ~p"/custom/alt-art?card=#{ctx.web_shooter.id}&creator=matt_murdock")

    assert has_element?(lv, "#gallery-empty", "No art found")
  end

  test "a malformed card filter is ignored", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom/alt-art?card=not-a-uuid")

    assert has_element?(lv, "#gallery-count", "3")
  end

  test "the set directory links to the gallery", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/custom")

    assert has_element?(lv, "#alt-art-gallery-link[href='/custom/alt-art']")
  end
end
