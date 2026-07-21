defmodule Sanctum.Search.CardFields do
  @moduledoc """
  Search-field registry for the card pool (queries run against
  `Sanctum.Games.CardSide`, where all printed card data lives).

  Shorthand letters follow MarvelCDB's smart-filter scheme where one exists
  (`t:` type, `a:` aspect, `x:` text, `k:` trait, `c:` cost, `e:` set) so
  muscle memory from MarvelCDB transfers.
  """

  @behaviour Sanctum.Search.Registry

  import Ash.Expr

  alias Sanctum.Games.{CardAspect, CardOwnership, CardType}
  alias Sanctum.Search.{Builders, Field}

  # `aspect` accepts the ownership pools too ("hero"/"basic"/…), matching the
  # pool page's filter pills, which conflate the two on purpose.
  @ownership_as_aspect ~w(hero basic encounter campaign player)

  @resource_counts %{
    "energy" => :resource_energy_count,
    "mental" => :resource_mental_count,
    "physical" => :resource_physical_count,
    "wild" => :resource_wild_count
  }

  @stat_fields [
    {"attack", ["atk"], :attack, "attack>=2"},
    {"thwart", ["thw"], :thwart, "thwart>=2"},
    {"defense", ["def"], :defense, "defense>=1"},
    {"health", ["hp"], :health, "health<=3"},
    {"recover", ["rec"], :recover, "recover>=3"},
    {"threat", [], :base_threat, "threat>=7"},
    {"escalation", [], :escalation_threat, "escalation>=1"},
    {"max_threat", ["maxthreat"], :max_threat, "max_threat<=10"}
  ]

  @int_fields [
    {"cost", ["c"], :cost, "cost<=2"},
    {"stage", [], :stage, "stage=3"},
    {"boost", ["b"], :boost, "boost>=2"},
    {"hand_size", ["hand"], :hand_size, "hand_size>=6"},
    {"energy", [], :resource_energy_count, "energy>=1"},
    {"mental", [], :resource_mental_count, "mental>=1"},
    {"physical", [], :resource_physical_count, "physical>=1"},
    {"wild", [], :resource_wild_count, "wild>=1"}
  ]

  @flags %{
    "unique" => :unique,
    "permanent" => :permanent,
    "multi_sided" => :multi_sided,
    "acceleration" => :acceleration,
    "amplify" => :amplify,
    "crisis" => :crisis,
    "hazard" => :hazard
  }

  @all_ops [:eq, :neq, :lt, :gt, :lte, :gte]

  @impl true
  def bare_word(value) do
    pattern = Builders.pattern(value)
    expr(ilike(name, ^pattern) or ilike(subname, ^pattern))
  end

  # Registry order doubles as autocomplete priority: the first ~10 fields are
  # what an empty search box offers.
  @impl true
  def fields do
    {cost_fields, other_int_fields} = Enum.split_with(int_fields(), &(&1.name == "cost"))

    primary_fields() ++
      cost_fields ++ stat_fields() ++ other_int_fields ++ misc_fields()
  end

  # -- field groups --------------------------------------------------------

  defp primary_fields do
    [
      %Field{
        name: "name",
        aliases: ["n"],
        kind: :text,
        example: ~s(name:"peter parker"),
        hint: "card or subtitle name",
        build: text_build(&name_expr/1)
      },
      %Field{
        name: "text",
        aliases: ["x"],
        kind: :text,
        example: ~s(text:"draw a card"),
        hint: "rules text",
        build: text_build(fn pattern -> expr(ilike(text, ^pattern)) end)
      },
      %Field{
        name: "type",
        aliases: ["t"],
        kind: :enum,
        values: enum_strings(CardType),
        example: "type:ally",
        hint: "card type",
        build:
          enum_build(CardType, fn atom, op ->
            Builders.cmp(expr(type), op, atom)
          end)
      },
      %Field{
        name: "aspect",
        aliases: ["a"],
        kind: :enum,
        values: enum_strings(CardAspect) ++ @ownership_as_aspect,
        example: "aspect:aggression",
        hint: "aspect, or a pool like hero/basic",
        build: &aspect_build/2
      },
      %Field{
        name: "trait",
        aliases: ["k", "traits"],
        kind: :text,
        example: "trait:avenger",
        hint: "card trait (Avenger, Skill, …)",
        values_fun: &Sanctum.Search.Values.traits/0,
        build: &trait_build/2
      }
    ]
  end

  defp misc_fields do
    [
      %Field{
        name: "resource",
        aliases: ["r"],
        kind: :enum,
        values: Map.keys(@resource_counts),
        example: "resource:mental",
        hint: "cards printing this resource",
        ops: [:eq],
        build: &resource_build/2
      },
      %Field{
        name: "ownership",
        aliases: ["o"],
        kind: :enum,
        values: enum_strings(CardOwnership),
        example: "ownership:encounter",
        hint: "which pool the card comes from",
        build:
          enum_build(CardOwnership, fn atom, op ->
            Builders.cmp(expr(ownership), op, atom)
          end)
      },
      %Field{
        name: "set",
        aliases: ["e"],
        kind: :text,
        example: "set:spider_man",
        hint: "card set",
        values_fun: &Sanctum.Search.Values.sets/0,
        build: text_build(fn pattern -> expr(ilike(card.set, ^pattern)) end)
      },
      %Field{
        name: "pack",
        aliases: ["p"],
        kind: :text,
        example: "pack:core",
        hint: "product/pack",
        values_fun: &Sanctum.Search.Values.packs/0,
        build: text_build(fn pattern -> expr(ilike(card.pack, ^pattern)) end)
      },
      Field.text(
        "flavor",
        ~s(flavor:avenger),
        "flavor text",
        text_build(fn pattern -> expr(ilike(flavor, ^pattern)) end)
      ),
      %Field{
        name: "code",
        aliases: [],
        kind: :text,
        example: "code:01001a",
        hint: "exact card code",
        build: fn op, value -> {:ok, Builders.cmp(expr(code), op, value)} end
      },
      %Field{
        name: "unique",
        aliases: ["u"],
        kind: :boolean,
        values: ["true", "false"],
        example: "unique:true",
        build: bool_build(fn bool, op -> Builders.cmp(expr(card.unique), op, bool) end)
      },
      %Field{
        name: "owned",
        aliases: [],
        kind: :boolean,
        values: ["true", "false"],
        example: "owned:true",
        hint: "in your collection (empty when signed out)",
        build: bool_build(fn bool, op -> Builders.cmp(expr(card.owned), op, bool) end)
      },
      %Field{
        name: "is",
        aliases: [],
        kind: :flag,
        values: @flags |> Map.keys() |> Enum.sort(),
        example: "is:unique",
        hint: "card properties and icons",
        ops: [:eq],
        build: &flag_build/2
      }
    ]
  end

  defp stat_fields do
    for {name, aliases, attr, example} <- @stat_fields do
      %Field{
        name: name,
        aliases: aliases,
        kind: :stat,
        example: example,
        ops: @all_ops,
        build: fn op, value ->
          with {:ok, n} <- Builders.parse_int(value) do
            {:ok, Builders.stat_cmp(attr, op, n)}
          end
        end
      }
    end
  end

  defp int_fields do
    for {name, aliases, attr, example} <- @int_fields do
      %Field{
        name: name,
        aliases: aliases,
        kind: :integer,
        example: example,
        ops: @all_ops,
        build: fn op, value ->
          with {:ok, n} <- Builders.parse_int(value) do
            {:ok, Builders.cmp(expr(^ref(attr)), op, n)}
          end
        end
      }
    end
  end

  # -- builders --------------------------------------------------------------

  defp name_expr(pattern) do
    expr(ilike(name, ^pattern) or ilike(subname, ^pattern))
  end

  defp text_build(to_expr) do
    fn
      :eq, value -> {:ok, to_expr.(Builders.pattern(value))}
      :neq, value -> {:ok, expr(not (^to_expr.(Builders.pattern(value))))}
    end
  end

  defp enum_build(enum_module, to_expr) do
    values = enum_module.values()

    fn op, value ->
      with {:ok, atom} <- Builders.coerce_enum(value, values) do
        {:ok, to_expr.(atom, op)}
      end
    end
  end

  defp bool_build(to_expr) do
    fn op, value ->
      with {:ok, bool} <- Builders.parse_bool(value) do
        {:ok, to_expr.(bool, op)}
      end
    end
  end

  # "hero"/"basic"/… filter ownership; the five real aspects filter aspect.
  defp aspect_build(op, value) do
    case Builders.coerce_enum(value, CardOwnership.values() ++ CardAspect.values()) do
      {:ok, atom} ->
        if to_string(atom) in @ownership_as_aspect do
          {:ok, Builders.cmp(expr(ownership), op, atom)}
        else
          {:ok, Builders.cmp(expr(aspect), op, atom)}
        end

      {:error, _} = error ->
        error
    end
  end

  # Each stored trait is used as the ILIKE pattern against the typed value,
  # giving a case-insensitive exact match per array element.
  defp trait_build(op, value) do
    match = expr(fragment("? ILIKE ANY (?)", ^value, traits))

    case op do
      :eq -> {:ok, match}
      :neq -> {:ok, expr(not (^match))}
    end
  end

  defp resource_build(:eq, value) do
    case Builders.coerce_enum(value, Map.keys(@resource_counts)) do
      {:ok, atom} ->
        attr = Map.fetch!(@resource_counts, to_string(atom))
        {:ok, expr(^ref(attr) >= 1)}

      {:error, _} = error ->
        error
    end
  end

  defp flag_build(:eq, value) do
    case Builders.coerce_enum(value, Map.keys(@flags)) do
      {:ok, atom} -> {:ok, flag_expr(Map.fetch!(@flags, to_string(atom)))}
      {:error, _} = error -> error
    end
  end

  defp flag_expr(:unique), do: expr(card.unique == true)
  defp flag_expr(:permanent), do: expr(card.permanent == true)
  defp flag_expr(:multi_sided), do: expr(card.is_multi_sided == true)
  defp flag_expr(:acceleration), do: expr(acceleration_icon == true)
  defp flag_expr(:amplify), do: expr(amplify_icon == true)
  defp flag_expr(:crisis), do: expr(crisis_icon == true)
  defp flag_expr(:hazard), do: expr(hazard_icon == true)

  defp enum_strings(enum_module), do: Enum.map(enum_module.values(), &to_string/1)
end
