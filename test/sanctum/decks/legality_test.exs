defmodule Sanctum.Decks.LegalityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Sanctum.Decks.Legality

  defp card(overrides) do
    side = %{
      name: Map.get(overrides, :name, "Test Card"),
      ownership: Map.get(overrides, :ownership, :basic),
      aspect: Map.get(overrides, :aspect),
      type: Map.get(overrides, :type),
      traits: Map.get(overrides, :traits, []),
      resource_energy_count: Map.get(overrides, :resource_energy_count, 0)
    }

    %{
      id: Map.get(overrides, :id, System.unique_integer([:positive])),
      code: Map.get(overrides, :code, "99999"),
      deck_limit: Map.get(overrides, :deck_limit, 3),
      unique: Map.get(overrides, :unique, false),
      permanent: Map.get(overrides, :permanent, false),
      primary_side: side
    }
  end

  defp entry(card, quantity, opts \\ []) do
    %{
      card: card,
      quantity: quantity,
      ignore_deck_limit: Keyword.get(opts, :ignore_deck_limit, false)
    }
  end

  defp codes(issues), do: issues |> Enum.map(& &1.code) |> Enum.sort()

  # 40 legal basic cards to pad decks up to size without other findings.
  defp filler(count) do
    {full, rest} = {div(count, 3), rem(count, 3)}

    fillers =
      for i <- 1..full//1 do
        entry(card(%{name: "Filler #{i}"}), 3)
      end

    if rest > 0 do
      [entry(card(%{name: "Filler rest"}), rest) | fillers]
    else
      fillers
    end
  end

  describe "deck size" do
    test "flags too few cards" do
      issues = Legality.issues(filler(39), [])

      assert [%Legality.Issue{code: :too_few, severity: :warning, message: message}] = issues
      assert message =~ "39"
    end

    test "flags too many cards" do
      assert [%Legality.Issue{code: :too_many, severity: :warning}] =
               Legality.issues(filler(51), [])
    end

    test "accepts 40-50 cards" do
      assert Legality.issues(filler(40), []) == []
      assert Legality.issues(filler(50), []) == []
    end

    test "permanent cards do not count toward deck size" do
      permanent = entry(card(%{permanent: true, name: "Permanent"}), 1)

      assert Legality.issues([permanent | filler(40)], []) == []
    end
  end

  describe "hero set" do
    test "flags missing and short signature cards" do
      sig_a = card(%{ownership: :hero, deck_limit: 2, name: "Backflip"})
      sig_b = card(%{ownership: :hero, deck_limit: 1, name: "Black Cat"})

      issues = Legality.issues([entry(sig_a, 1) | filler(39)], [sig_a, sig_b])

      assert [
               %{code: :hero_set_incomplete, card_id: a_id},
               %{code: :hero_set_incomplete, card_id: b_id}
             ] = Enum.filter(issues, &(&1.code == :hero_set_incomplete))

      assert a_id == sig_a.id
      assert b_id == sig_b.id
    end

    test "flags hero-ownership cards beyond the signature set" do
      sig = card(%{ownership: :hero, deck_limit: 2, name: "Backflip"})
      stray = card(%{ownership: :hero, deck_limit: 1, name: "Other Hero Card"})

      issues =
        Legality.issues(
          [entry(sig, 3), entry(stray, 1) | filler(36)],
          [sig]
        )

      extras = Enum.filter(issues, &(&1.code == :hero_set_extra))

      assert Enum.map(extras, & &1.card_id) |> Enum.sort() ==
               Enum.sort([sig.id, stray.id])
    end

    test "exact signature set raises no hero issues" do
      sig = card(%{ownership: :hero, deck_limit: 2, name: "Backflip"})

      issues = Legality.issues([entry(sig, 2) | filler(38)], [sig])

      refute Enum.any?(issues, &(&1.code in [:hero_set_incomplete, :hero_set_extra]))
    end
  end

  describe "copy limits" do
    test "flags quantities over deck_limit" do
      over = card(%{deck_limit: 3, name: "Over Limit"})

      issues = Legality.issues([entry(over, 4) | filler(36)], [])

      assert [%{code: :deck_limit_exceeded, severity: :error, card_id: card_id}] =
               Enum.filter(issues, &(&1.code == :deck_limit_exceeded))

      assert card_id == over.id
    end

    test "ignore_deck_limit suppresses the deck_limit finding" do
      over = card(%{deck_limit: 3, name: "Boosted"})

      issues = Legality.issues([entry(over, 4, ignore_deck_limit: true) | filler(36)], [])

      refute Enum.any?(issues, &(&1.code == :deck_limit_exceeded))
    end

    test "flags duplicate uniques (without doubling up a deck_limit finding)" do
      uniq = card(%{unique: true, deck_limit: 1, name: "Unique Ally"})

      issues = Legality.issues([entry(uniq, 2) | filler(38)], [])

      assert [%{code: :unique_dup, severity: :error}] =
               Enum.filter(issues, &(&1.code in [:unique_dup, :deck_limit_exceeded]))
    end
  end

  describe "aspect inference" do
    test "aspects_from_entries returns the sorted distinct player aspects" do
      justice = card(%{ownership: :player, aspect: "justice"})
      aggression = card(%{ownership: :player, aspect: "aggression"})

      entries = [entry(aggression, 2), entry(justice, 3)]

      assert Legality.aspects_from_entries(entries) == ["aggression", "justice"]
    end

    test "a single represented aspect infers just that aspect" do
      justice = card(%{ownership: :player, aspect: "justice"})

      assert Legality.aspects_from_entries([entry(justice, 3)]) == ["justice"]
    end

    test "removing every copy drops the aspect (quantity 0 doesn't count)" do
      justice = card(%{ownership: :player, aspect: "justice"})

      assert Legality.aspects_from_entries([entry(justice, 0)]) == []
    end

    test "hero and basic cards never contribute an aspect" do
      basic = card(%{ownership: :basic, aspect: nil})
      hero = card(%{ownership: :hero, aspect: nil, deck_limit: 2})

      assert Legality.aspects_from_entries([entry(basic, 3), entry(hero, 2)]) == []
    end
  end

  describe "multi-aspect advisory" do
    test "flags a deck that combines more than one aspect" do
      justice = card(%{ownership: :player, aspect: "justice", name: "Justice Card"})
      pool = card(%{ownership: :player, aspect: "pool", name: "Pool Card"})

      issues = Legality.issues([entry(justice, 3), entry(pool, 3) | filler(34)], [])

      assert [%{code: :multi_aspect, severity: :warning, message: message}] =
               Enum.filter(issues, &(&1.code == :multi_aspect))

      assert message =~ "2 aspects"
      assert message =~ "'Pool"
    end

    test "a single-aspect deck raises no multi-aspect issue" do
      justice = card(%{ownership: :player, aspect: "justice"})

      issues = Legality.issues([entry(justice, 3) | filler(37)], [])

      refute Enum.any?(issues, &(&1.code == :multi_aspect))
    end

    test "basic and hero cards never raise a multi-aspect issue" do
      basic = card(%{ownership: :basic, aspect: nil})
      hero = card(%{ownership: :hero, aspect: nil, deck_limit: 2})

      issues = Legality.issues([entry(basic, 3), entry(hero, 2) | filler(35)], [hero])

      refute Enum.any?(issues, &(&1.code == :multi_aspect))
    end
  end

  describe "hero-specific exceptions (HeroRules)" do
    test "Spider-Woman may run two aspects without a multi-aspect warning" do
      justice = card(%{ownership: :player, aspect: "justice"})
      leadership = card(%{ownership: :player, aspect: "leadership"})

      issues =
        Legality.issues(
          [entry(justice, 3), entry(leadership, 3) | filler(34)],
          [],
          "spider_woman"
        )

      refute Enum.any?(issues, &(&1.code == :multi_aspect))
    end

    test "Spider-Woman with lopsided aspects gets an equal-count advisory" do
      justice = card(%{ownership: :player, aspect: "justice"})
      leadership = card(%{ownership: :player, aspect: "leadership"})

      issues =
        Legality.issues(
          [entry(justice, 3), entry(leadership, 1) | filler(36)],
          [],
          "spider_woman"
        )

      assert [%{code: :unequal_aspects, severity: :warning}] =
               Enum.filter(issues, &(&1.code == :unequal_aspects))
    end

    test "Adam Warlock may run four aspects and is capped at one copy per card" do
      aggression = card(%{ownership: :player, aspect: "aggression"})
      justice = card(%{ownership: :player, aspect: "justice"})
      leadership = card(%{ownership: :player, aspect: "leadership"})
      protection = card(%{ownership: :player, aspect: "protection", name: "Warded"})

      # Single copies of 36 distinct basics — Warlock's rule applies to every
      # card, so qty-3 fillers would (correctly) flag too.
      singles = for i <- 1..36//1, do: entry(card(%{name: "Single #{i}"}), 1)

      entries = [
        entry(aggression, 1),
        entry(justice, 1),
        entry(leadership, 1),
        # Only this card breaks the single-copy rule.
        entry(protection, 2)
        | singles
      ]

      issues = Legality.issues(entries, [], "warlock")

      refute Enum.any?(issues, &(&1.code == :multi_aspect))

      assert [%{code: :deck_limit_exceeded, card_id: id}] =
               Enum.filter(issues, &(&1.code == :deck_limit_exceeded))

      assert id == protection.id
    end

    test "Gamora allows up to 6 off-aspect attack/thwart events" do
      # Chosen aspect dominates; a few off-aspect attack events ride along.
      justice = card(%{ownership: :player, aspect: "justice"})

      off =
        card(%{ownership: :player, aspect: "aggression", type: :event, traits: ["Attack"]})

      issues = Legality.issues([entry(justice, 10), entry(off, 3) | filler(27)], [], "gam")

      refute Enum.any?(
               issues,
               &(&1.code in [:multi_aspect, :off_aspect_over_limit, :off_aspect_not_events])
             )
    end

    test "Gamora warns when off-aspect cards aren't attack/thwart events" do
      justice = card(%{ownership: :player, aspect: "justice"})
      off = card(%{ownership: :player, aspect: "aggression", type: :ally, traits: []})

      issues = Legality.issues([entry(justice, 10), entry(off, 1) | filler(29)], [], "gam")

      assert Enum.any?(issues, &(&1.code == :off_aspect_not_allowed))
    end

    test "Cyclops allows unlimited off-aspect X-Men allies" do
      justice = card(%{ownership: :player, aspect: "justice"})
      xmen = card(%{ownership: :player, aspect: "aggression", type: :ally, traits: ["X-Men"]})

      issues = Legality.issues([entry(justice, 10), entry(xmen, 3) | filler(27)], [], "cyclops")

      refute Enum.any?(
               issues,
               &(&1.code in [:multi_aspect, :off_aspect_not_allowed, :off_aspect_over_limit])
             )
    end

    test "Cyclops warns on off-aspect cards that aren't X-Men allies" do
      justice = card(%{ownership: :player, aspect: "justice"})
      # An off-aspect upgrade (not an ally) doesn't qualify.
      off = card(%{ownership: :player, aspect: "aggression", type: :upgrade, traits: ["X-Men"]})

      issues = Legality.issues([entry(justice, 10), entry(off, 1) | filler(29)], [], "cyclops")

      assert Enum.any?(issues, &(&1.code == :off_aspect_not_allowed))
    end

    test "Maria Hill allows up to 3 off-aspect S.H.I.E.L.D. supports (trait spelling tolerant)" do
      justice = card(%{ownership: :player, aspect: "justice"})
      # Note the period-less trait spelling — matching must tolerate it.
      s1 =
        card(%{ownership: :player, aspect: "leadership", type: :support, traits: ["S.H.I.E.L.D"]})

      s2 =
        card(%{
          ownership: :player,
          aspect: "leadership",
          type: :support,
          traits: ["S.H.I.E.L.D."]
        })

      s3 =
        card(%{ownership: :player, aspect: "leadership", type: :support, traits: ["S.H.I.E.L.D"]})

      entries = [entry(justice, 10), entry(s1, 2), entry(s2, 2), entry(s3, 2) | filler(24)]
      issues = Legality.issues(entries, [], "maria_hill")

      refute Enum.any?(
               issues,
               &(&1.code in [:multi_aspect, :off_aspect_not_allowed, :off_aspect_over_limit])
             )
    end

    test "Cable allows off-aspect player side schemes (type-only allowance)" do
      justice = card(%{ownership: :player, aspect: "justice"})

      scheme =
        card(%{ownership: :player, aspect: "aggression", type: :player_side_scheme, traits: []})

      issues = Legality.issues([entry(justice, 10), entry(scheme, 1) | filler(29)], [], "cable")

      refute Enum.any?(
               issues,
               &(&1.code in [:multi_aspect, :off_aspect_not_allowed, :off_aspect_over_limit])
             )
    end

    test "Cable warns on off-aspect cards that aren't player side schemes" do
      justice = card(%{ownership: :player, aspect: "justice"})
      off = card(%{ownership: :player, aspect: "aggression", type: :ally, traits: []})

      issues = Legality.issues([entry(justice, 10), entry(off, 1) | filler(29)], [], "cable")

      assert Enum.any?(issues, &(&1.code == :off_aspect_not_allowed))
    end

    test "Wonder Man allows off-aspect events with a printed energy resource" do
      justice = card(%{ownership: :player, aspect: "justice"})

      ionic =
        card(%{
          ownership: :player,
          aspect: "aggression",
          type: :event,
          resource_energy_count: 1
        })

      issues =
        Legality.issues([entry(justice, 10), entry(ionic, 3) | filler(27)], [], "wonder_man")

      refute Enum.any?(
               issues,
               &(&1.code in [:multi_aspect, :off_aspect_not_allowed, :off_aspect_over_limit])
             )
    end

    test "Wonder Man warns on off-aspect events without an energy resource" do
      justice = card(%{ownership: :player, aspect: "justice"})
      # An off-aspect event with no printed energy pip doesn't qualify.
      plain =
        card(%{ownership: :player, aspect: "aggression", type: :event, resource_energy_count: 0})

      issues =
        Legality.issues([entry(justice, 10), entry(plain, 1) | filler(29)], [], "wonder_man")

      assert Enum.any?(issues, &(&1.code == :off_aspect_not_allowed))
    end

    test "Maria Hill warns beyond 3 distinct off-aspect S.H.I.E.L.D. supports" do
      justice = card(%{ownership: :player, aspect: "justice"})

      supports =
        for i <- 1..4//1 do
          entry(
            card(%{
              ownership: :player,
              aspect: "leadership",
              type: :support,
              traits: ["S.H.I.E.L.D."],
              name: "SHIELD #{i}"
            }),
            1
          )
        end

      issues = Legality.issues([entry(justice, 10) | supports] ++ filler(26), [], "maria_hill")

      assert Enum.any?(issues, &(&1.code == :off_aspect_over_limit))
    end

    test "Gamora warns when more than 6 off-aspect cards are included" do
      justice = card(%{ownership: :player, aspect: "justice"})
      # Chosen aspect dominates (as a real Gamora deck does); off-aspect attack
      # events spread across cards total 7 > 6.
      off_a = card(%{ownership: :player, aspect: "aggression", type: :event, traits: ["Attack"]})
      off_b = card(%{ownership: :player, aspect: "aggression", type: :event, traits: ["Attack"]})
      off_c = card(%{ownership: :player, aspect: "aggression", type: :event, traits: ["Thwart"]})

      entries =
        [entry(justice, 10), entry(off_a, 3), entry(off_b, 3), entry(off_c, 1) | filler(23)]

      issues = Legality.issues(entries, [], "gam")

      assert Enum.any?(issues, &(&1.code == :off_aspect_over_limit))
    end
  end

  test "a legal-looking single-aspect deck returns no issues" do
    sig = card(%{ownership: :hero, deck_limit: 2, name: "Signature"})
    aspect_card = card(%{ownership: :player, aspect: "justice", name: "Aspect Card"})

    entries = [entry(sig, 2), entry(aspect_card, 3) | filler(35)]

    assert Legality.issues(entries, [sig]) == []
  end

  test "issue codes are stable atoms (UI contract)" do
    issues = Legality.issues(filler(10), [])
    assert Enum.all?(issues, &match?(%Legality.Issue{}, &1))
    assert codes(issues) == [:too_few]
  end
end
