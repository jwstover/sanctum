defmodule Sanctum.Decks.LegalityTest do
  @moduledoc false

  use ExUnit.Case, async: true

  alias Sanctum.Decks.Legality

  defp card(overrides) do
    side = %{
      name: Map.get(overrides, :name, "Test Card"),
      ownership: Map.get(overrides, :ownership, :basic),
      aspect: Map.get(overrides, :aspect)
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
      issues = Legality.issues(filler(39), [], [])

      assert [%Legality.Issue{code: :too_few, severity: :warning, message: message}] = issues
      assert message =~ "39"
    end

    test "flags too many cards" do
      assert [%Legality.Issue{code: :too_many, severity: :warning}] =
               Legality.issues(filler(51), [], [])
    end

    test "accepts 40-50 cards" do
      assert Legality.issues(filler(40), [], []) == []
      assert Legality.issues(filler(50), [], []) == []
    end

    test "permanent cards do not count toward deck size" do
      permanent = entry(card(%{permanent: true, name: "Permanent"}), 1)

      assert Legality.issues([permanent | filler(40)], [], []) == []
    end
  end

  describe "hero set" do
    test "flags missing and short signature cards" do
      sig_a = card(%{ownership: :hero, deck_limit: 2, name: "Backflip"})
      sig_b = card(%{ownership: :hero, deck_limit: 1, name: "Black Cat"})

      issues = Legality.issues([entry(sig_a, 1) | filler(39)], [], [sig_a, sig_b])

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
          [],
          [sig]
        )

      extras = Enum.filter(issues, &(&1.code == :hero_set_extra))

      assert Enum.map(extras, & &1.card_id) |> Enum.sort() ==
               Enum.sort([sig.id, stray.id])
    end

    test "exact signature set raises no hero issues" do
      sig = card(%{ownership: :hero, deck_limit: 2, name: "Backflip"})

      issues = Legality.issues([entry(sig, 2) | filler(38)], [], [sig])

      refute Enum.any?(issues, &(&1.code in [:hero_set_incomplete, :hero_set_extra]))
    end
  end

  describe "copy limits" do
    test "flags quantities over deck_limit" do
      over = card(%{deck_limit: 3, name: "Over Limit"})

      issues = Legality.issues([entry(over, 4) | filler(36)], [], [])

      assert [%{code: :deck_limit_exceeded, severity: :error, card_id: card_id}] =
               Enum.filter(issues, &(&1.code == :deck_limit_exceeded))

      assert card_id == over.id
    end

    test "ignore_deck_limit suppresses the deck_limit finding" do
      over = card(%{deck_limit: 3, name: "Boosted"})

      issues = Legality.issues([entry(over, 4, ignore_deck_limit: true) | filler(36)], [], [])

      refute Enum.any?(issues, &(&1.code == :deck_limit_exceeded))
    end

    test "flags duplicate uniques (without doubling up a deck_limit finding)" do
      uniq = card(%{unique: true, deck_limit: 1, name: "Unique Ally"})

      issues = Legality.issues([entry(uniq, 2) | filler(38)], [], [])

      assert [%{code: :unique_dup, severity: :error}] =
               Enum.filter(issues, &(&1.code in [:unique_dup, :deck_limit_exceeded]))
    end
  end

  describe "aspects" do
    test "flags player cards outside the deck's aspects" do
      justice = card(%{ownership: :player, aspect: "justice", name: "Justice Card"})
      pool = card(%{ownership: :player, aspect: "pool", name: "Pool Card"})

      issues =
        Legality.issues(
          [entry(justice, 3), entry(pool, 3) | filler(34)],
          ["justice"],
          []
        )

      assert [%{code: :off_aspect, severity: :warning, card_id: card_id, message: message}] =
               Enum.filter(issues, &(&1.code == :off_aspect))

      assert card_id == pool.id
      assert message =~ "'Pool"
    end

    test "multi-aspect decks accept cards from every chosen aspect" do
      justice = card(%{ownership: :player, aspect: "justice"})
      pool = card(%{ownership: :player, aspect: "pool"})

      issues =
        Legality.issues(
          [entry(justice, 3), entry(pool, 3) | filler(34)],
          ["justice", "pool"],
          []
        )

      refute Enum.any?(issues, &(&1.code == :off_aspect))
    end

    test "a basic deck (no aspects) flags every player aspect card" do
      justice = card(%{ownership: :player, aspect: "justice"})

      issues = Legality.issues([entry(justice, 3) | filler(37)], [], [])

      assert Enum.any?(issues, &(&1.code == :off_aspect))
    end

    test "basic and hero cards never raise aspect issues" do
      basic = card(%{ownership: :basic, aspect: nil})
      hero = card(%{ownership: :hero, aspect: nil, deck_limit: 2})

      issues = Legality.issues([entry(basic, 3), entry(hero, 2) | filler(35)], [], [hero])

      refute Enum.any?(issues, &(&1.code == :off_aspect))
    end
  end

  test "a legal-looking deck returns no issues" do
    sig = card(%{ownership: :hero, deck_limit: 2, name: "Signature"})
    aspect_card = card(%{ownership: :player, aspect: "justice", name: "Aspect Card"})

    entries = [entry(sig, 2), entry(aspect_card, 3) | filler(35)]

    assert Legality.issues(entries, ["justice"], [sig]) == []
  end

  test "issue codes are stable atoms (UI contract)" do
    issues = Legality.issues(filler(10), [], [])
    assert Enum.all?(issues, &match?(%Legality.Issue{}, &1))
    assert codes(issues) == [:too_few]
  end
end
