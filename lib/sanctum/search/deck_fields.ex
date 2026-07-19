defmodule Sanctum.Search.DeckFields do
  @moduledoc """
  Search-field registry for the deck browser (queries run against
  `Sanctum.Decks.Deck`).
  """

  @behaviour Sanctum.Search.Registry

  import Ash.Expr

  alias Sanctum.Decks.{DeckAspect, DeckSource}
  alias Sanctum.Search.{Builders, Field}

  @all_ops [:eq, :neq, :lt, :gt, :lte, :gte]

  @impl true
  def bare_word(value) do
    pattern = Builders.pattern(value)
    expr(ilike(title, ^pattern) or ilike(hero.hero_name, ^pattern))
  end

  @impl true
  def fields do
    [
      %Field{
        name: "title",
        aliases: [],
        kind: :text,
        example: ~s(title:"web warriors"),
        hint: "deck title",
        build: text_build(fn pattern -> expr(ilike(title, ^pattern)) end)
      },
      %Field{
        name: "hero",
        aliases: ["h"],
        kind: :text,
        example: "hero:spider-man",
        hint: "hero or alter-ego name",
        values_fun: &Sanctum.Search.Values.heroes/0,
        build:
          text_build(fn pattern ->
            # display_name always contains hero_name, so it subsumes a
            # hero_name match while also matching the disambiguated
            # "Black Panther (T'Challa)" suggestions.
            expr(ilike(hero.display_name, ^pattern) or ilike(hero.alter_ego_name, ^pattern))
          end)
      },
      %Field{
        name: "aspect",
        aliases: ["a"],
        kind: :enum,
        values: Enum.map(DeckAspect.values(), &to_string/1) ++ ["basic"],
        example: "aspect:justice",
        hint: "aspect the deck plays (basic = none)",
        ops: [:eq, :neq],
        build: &aspect_build/2
      },
      %Field{
        name: "card",
        aliases: ["includes"],
        kind: :text,
        example: ~s(card:"boot camp"),
        hint: "decks containing a card",
        build:
          text_build(fn pattern ->
            expr(exists(cards.card_sides, ilike(name, ^pattern)))
          end)
      },
      %Field{
        name: "cards",
        aliases: [],
        kind: :integer,
        example: "cards>=45",
        hint: "total card count",
        ops: @all_ops,
        build: fn op, value ->
          with {:ok, n} <- Builders.parse_int(value) do
            {:ok, Builders.cmp(expr(total_card_count), op, n)}
          end
        end
      },
      %Field{
        name: "source",
        aliases: [],
        kind: :enum,
        values: Enum.map(DeckSource.values(), &to_string/1),
        example: "source:marvelcdb",
        build: fn op, value ->
          with {:ok, atom} <- Builders.coerce_enum(value, DeckSource.values()) do
            {:ok, Builders.cmp(expr(source), op, atom)}
          end
        end
      }
    ]
  end

  defp text_build(to_expr) do
    fn
      :eq, value -> {:ok, to_expr.(Builders.pattern(value))}
      :neq, value -> {:ok, expr(not (^to_expr.(Builders.pattern(value))))}
    end
  end

  # A deck's aspects are an array; an empty array is a basic deck.
  defp aspect_build(op, value) do
    case Builders.coerce_enum(value, DeckAspect.values() ++ ["basic"]) do
      {:ok, "basic"} ->
        wrap_neq(op, expr(fragment("cardinality(?) = 0", aspects)))

      {:ok, atom} ->
        wrap_neq(op, expr(^atom in aspects))

      {:error, _} = error ->
        error
    end
  end

  defp wrap_neq(:eq, e), do: {:ok, e}
  defp wrap_neq(:neq, e), do: {:ok, expr(not (^e))}
end
