defmodule Sanctum.Search.Global do
  @moduledoc """
  Site-wide search: one query string fanned out across every content type.

  Reuses the `Sanctum.Search` query language with cross-type semantics:

    * a reserved **top-level `in:` qualifier** scopes the search to specific
      types (`in:cards`, `in:decks|heroes`); it is extracted before
      compilation and never reaches a registry
    * the remaining query is compiled once per type registry; a type is
      **excluded** when any clause references a field, operator, or value its
      registry doesn't understand — so `cost<=2` implicitly narrows to cards
      while `aspect:aggression` spans cards and decks
    * bare words fall through to each registry's name matching, so `spider`
      finds cards, decks, heroes, packs, …

  Returns display-ready result groups in a fixed order with per-type limits.
  Queries run against lightweight default `:read` actions (not the heavy
  `:browse` actions the pool/deck browsers use).
  """

  require Ash.Query
  require Logger

  alias Sanctum.Search.{Compiler, Diagnostic, Field, Parser, Registry, Token}

  alias Sanctum.Search.{
    CardFields,
    CardSetFields,
    DeckFields,
    HeroFields,
    PackFields,
    ScenarioFields,
    VillainFields
  }

  @default_limit 5
  @scoped_limit 15

  # Fixed display order of result groups.
  @types [
    %{key: :cards, label: "Cards", registry: CardFields},
    %{key: :decks, label: "Decks", registry: DeckFields},
    %{key: :heroes, label: "Heroes", registry: HeroFields},
    %{key: :packs, label: "Packs", registry: PackFields},
    %{key: :card_sets, label: "Card Sets", registry: CardSetFields},
    %{key: :villains, label: "Villains", registry: VillainFields},
    %{key: :scenarios, label: "Scenarios", registry: ScenarioFields}
  ]

  @type_aliases %{
    "card" => :cards,
    "cards" => :cards,
    "deck" => :decks,
    "decks" => :decks,
    "hero" => :heroes,
    "heroes" => :heroes,
    "pack" => :packs,
    "packs" => :packs,
    "set" => :card_sets,
    "sets" => :card_sets,
    "card_set" => :card_sets,
    "card_sets" => :card_sets,
    "villain" => :villains,
    "villains" => :villains,
    "scenario" => :scenarios,
    "scenarios" => :scenarios
  }

  @type result :: %{
          id: term(),
          title: String.t(),
          subtitle: String.t() | nil,
          href: String.t() | nil,
          kind: atom()
        }

  @type group :: %{
          type: atom(),
          label: String.t(),
          results: [result()],
          more?: boolean(),
          more_url: String.t() | nil
        }

  @doc "The canonical `in:` values, for autocomplete and docs."
  @spec type_values() :: [String.t()]
  def type_values, do: Enum.map(@types, &to_string(&1.key))

  @doc "The per-type registries in display order, as `{key, label, registry}`."
  @spec types() :: [%{key: atom(), label: String.t(), registry: module()}]
  def types, do: @types

  @doc """
  Cursor-context autocomplete for the global search bar.

  When the query is scoped to exactly one type via `in:`, suggestions come
  from that type's registry; otherwise from `Sanctum.Search.GlobalFields`
  (the `in:` qualifier plus the union of every registry's fields). Reply
  shape matches `Sanctum.Search.Suggest.suggest/3`.
  """
  @spec suggest(String.t(), non_neg_integer()) :: map()
  def suggest(input, cursor_utf16) when is_binary(input) do
    {ast, _diags} = Parser.parse(input)
    {scope, _rest, _spans, _diags} = extract_scope(ast)

    registry =
      with types when types != :all <- scope,
           [single] <- MapSet.to_list(types),
           %{registry: registry} <- Enum.find(@types, &(&1.key == single)) do
        registry
      else
        _ -> Sanctum.Search.GlobalFields
      end

    Sanctum.Search.Suggest.suggest(input, cursor_utf16, registry)
  end

  @doc """
  Run a global search. Returns `%{groups:, diagnostics:}` where `groups` only
  contains types with at least one result. Empty/whitespace input — or a
  query with no usable terms and no `in:` scope — returns no groups.
  """
  @spec search(String.t(), term(), keyword()) :: %{
          groups: [group()],
          diagnostics: [Diagnostic.t()]
        }
  def search(input, actor, opts \\ []) when is_binary(input) do
    if String.trim(input) == "" do
      %{groups: [], diagnostics: []}
    else
      do_search(input, actor, opts)
    end
  end

  defp do_search(input, actor, opts) do
    {ast, parse_diags} = Parser.parse(input)
    {scope, rest_ast, spans, scope_diags} = extract_scope(ast)
    rest = remainder(input, spans)

    requested =
      case scope do
        :all -> Enum.map(@types, & &1.key)
        set -> Enum.filter(Enum.map(@types, & &1.key), &(&1 in set))
      end

    limit =
      Keyword.get_lazy(opts, :limit, fn ->
        if length(requested) == 1, do: @scoped_limit, else: @default_limit
      end)

    if rest_ast == nil and scope == :all do
      # Nothing usable was typed (yet): don't list the whole catalog.
      %{groups: [], diagnostics: parse_diags ++ scope_diags}
    else
      {groups, compile_diags} = run(requested, rest_ast, rest, actor, limit)

      # Per-type compile diagnostics (partially-invalid values) are only
      # meaningful when the search is scoped to one type; across types they
      # contradict the groups that did match.
      diags =
        if length(requested) == 1,
          do: parse_diags ++ scope_diags ++ compile_diags,
          else: parse_diags ++ scope_diags

      %{groups: groups, diagnostics: Enum.uniq(diags)}
    end
  end

  defp run(requested, ast, rest, actor, limit) do
    Enum.reduce(@types, {[], []}, fn spec, {groups, diags} ->
      if spec.key in requested and applicable?(ast, spec.registry) do
        {expr, compile_diags} = Compiler.compile(ast, spec.registry)
        records = fetch(spec.key, expr, actor, limit + 1)
        results = records |> Enum.take(limit) |> to_results(spec.key, actor)

        group = %{
          type: spec.key,
          label: spec.label,
          results: results,
          more?: length(records) > limit,
          more_url: more_url(spec.key, rest)
        }

        {if(results == [], do: groups, else: groups ++ [group]), diags ++ compile_diags}
      else
        {groups, diags}
      end
    end)
  end

  # -- scope extraction --------------------------------------------------------

  @doc """
  Extract top-level `in:` qualifiers from a parsed AST.

  Returns `{scope, remainder_ast, removed_spans, diagnostics}` where `scope`
  is `:all` or a `MapSet` of type keys, and `removed_spans` are byte spans of
  the extracted clauses in the original input (for `remainder/2`).
  """
  @spec extract_scope(Parser.ast() | nil) ::
          {:all | MapSet.t(atom()), Parser.ast() | nil, [{non_neg_integer(), non_neg_integer()}],
           [Diagnostic.t()]}
  def extract_scope(nil), do: {:all, nil, [], []}

  def extract_scope(ast) do
    {scope_clauses, rest_ast} =
      case ast do
        {:clause, _} = clause ->
          if in_clause?(clause), do: {[clause], nil}, else: {[], ast}

        {:and, children} ->
          {ins, rest} = Enum.split_with(children, &in_clause?/1)
          {ins, and_node(rest)}

        other ->
          {[], other}
      end

    {rest_ast, nested_spans, nested_diags} = scrub_nested(rest_ast)

    {types, type_diags} =
      scope_clauses
      |> Enum.flat_map(fn {:clause, %{values: values}} -> values end)
      |> Enum.reduce({[], []}, fn %Token{} = tok, {types, diags} ->
        case Map.get(@type_aliases, Registry.normalize(tok.value)) do
          nil -> {types, diags ++ [unknown_type(tok)]}
          key -> {types ++ [key], diags}
        end
      end)

    spans = Enum.map(scope_clauses, &clause_span/1) ++ nested_spans
    scope = if types == [], do: :all, else: MapSet.new(types)

    {scope, rest_ast, spans, type_diags ++ nested_diags}
  end

  defp in_clause?({:clause, %{field: %Token{value: v}}}), do: Registry.normalize(v) == "in"
  defp in_clause?(_node), do: false

  defp clause_span({:clause, %{field: field_tok, values: values}}) do
    last = List.last(values)
    {field_tok.start, last.start + last.length - field_tok.start}
  end

  # Remove `in:` clauses hiding below the top level (inside or/not/parens):
  # scoping a disjunct has no defensible meaning, so warn and drop.
  defp scrub_nested(nil), do: {nil, [], []}

  defp scrub_nested({:and, children}), do: scrub_children(:and, children)
  defp scrub_nested({:or, children}), do: scrub_children(:or, children)

  defp scrub_nested({:not, child}) do
    {node, spans, diags} = scrub_nested(child)
    {if(node, do: {:not, node}), spans, diags}
  end

  defp scrub_nested({:clause, _} = clause) do
    if in_clause?(clause) do
      {start, length} = clause_span(clause)

      diag =
        Diagnostic.new(
          :warning,
          :misplaced_scope,
          ~s("in:" only works as a top-level filter),
          start,
          length
        )

      {nil, [{start, length}], [diag]}
    else
      {clause, [], []}
    end
  end

  defp scrub_nested({:word, _} = word), do: {word, [], []}

  defp scrub_children(kind, children) do
    {nodes, spans, diags} =
      Enum.reduce(children, {[], [], []}, fn child, {nodes, spans, diags} ->
        {node, s, d} = scrub_nested(child)
        {if(node, do: nodes ++ [node], else: nodes), spans ++ s, diags ++ d}
      end)

    node =
      case nodes do
        [] -> nil
        [one] -> one
        many -> {kind, many}
      end

    {node, spans, diags}
  end

  defp and_node([]), do: nil
  defp and_node([one]), do: one
  defp and_node(children), do: {:and, children}

  defp unknown_type(%Token{} = tok) do
    Diagnostic.new(
      :warning,
      :unknown_type,
      ~s("#{tok.value}" isn't a searchable type — try #{Enum.join(type_values(), ", ")}),
      tok.start,
      tok.length
    )
  end

  # -- per-type applicability ---------------------------------------------------

  @doc """
  Whether every clause in `ast` is understood by `registry` (field known,
  operator supported, at least one value valid). Types failing this check are
  excluded from the fan-out rather than compiled leniently — `cost<=2` should
  narrow the search to cards, not show a decks group that matches nothing.
  """
  @spec applicable?(Parser.ast() | nil, module()) :: boolean()
  def applicable?(nil, _registry), do: true
  def applicable?({:and, children}, registry), do: Enum.all?(children, &applicable?(&1, registry))
  def applicable?({:or, children}, registry), do: Enum.all?(children, &applicable?(&1, registry))
  def applicable?({:not, child}, registry), do: applicable?(child, registry)
  def applicable?({:word, _}, _registry), do: true

  def applicable?({:clause, %{field: field_tok, op: op, values: values}}, registry) do
    case Registry.lookup(registry, field_tok.value) do
      nil ->
        false

      %Field{} = field ->
        op in field.ops and
          Enum.any?(values, fn %Token{value: v} -> match?({:ok, _}, field.build.(op, v)) end)
    end
  end

  # -- remainder serialization ---------------------------------------------------

  @doc """
  The original input with the given byte spans (extracted `in:` clauses)
  spliced out — suitable for `/cards?query=…` / `/decks?query=…` deep links
  that recompile identically on the target page.
  """
  @spec remainder(String.t(), [{non_neg_integer(), non_neg_integer()}]) :: String.t()
  def remainder(input, []), do: String.trim(input)

  def remainder(input, spans) do
    spans
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.reduce(input, &splice(&2, &1))
    |> String.trim()
  end

  # Splice out a span plus one adjacent whitespace run, so the remainder never
  # gains doubled spaces (and quoted values keep their inner whitespace).
  defp splice(input, {start, length}) do
    stop = start + length
    trailing_ws = count_ws(input, stop, byte_size(input))
    leading_ws = if trailing_ws == 0, do: count_ws_before(input, start), else: 0

    prefix = binary_part(input, 0, start - leading_ws)
    rest_start = stop + trailing_ws
    prefix <> binary_part(input, rest_start, byte_size(input) - rest_start)
  end

  defp count_ws(input, at, size) when at < size do
    case binary_part(input, at, 1) do
      ws when ws in [" ", "\t"] -> 1 + count_ws(input, at + 1, size)
      _ -> 0
    end
  end

  defp count_ws(_input, _at, _size), do: 0

  defp count_ws_before(input, at) when at > 0 do
    case binary_part(input, at - 1, 1) do
      ws when ws in [" ", "\t"] -> 1 + count_ws_before(input, at - 1)
      _ -> 0
    end
  end

  defp count_ws_before(_input, _at), do: 0

  # -- fetch + result shaping ----------------------------------------------------

  defp fetch(key, expr, actor, limit) do
    do_fetch(key, expr, actor, limit)
  rescue
    error ->
      Logger.error(
        "global search #{key} query failed: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      []
  end

  defp do_fetch(:cards, expr, actor, limit) do
    Sanctum.Games.CardSide
    |> base_query(expr)
    |> Ash.Query.sort(code: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load(card: [:pack_ref])
    |> Ash.read!(actor: actor)
  end

  defp do_fetch(:decks, expr, actor, limit) do
    Sanctum.Decks.Deck
    |> base_query(expr)
    |> Ash.Query.sort(updated_at: :desc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load(hero: [:display_name])
    |> Ash.read!(actor: actor)
  end

  defp do_fetch(:heroes, expr, actor, limit) do
    Sanctum.Heroes.Hero
    |> base_query(expr)
    |> Ash.Query.sort(hero_name: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load(:display_name)
    |> Ash.read!(actor: actor)
  end

  defp do_fetch(:packs, expr, actor, limit) do
    Sanctum.Catalog.Pack
    |> base_query(expr)
    |> Ash.Query.sort(position: :asc_nils_last)
    |> Ash.Query.limit(limit)
    |> Ash.read!(actor: actor)
  end

  defp do_fetch(:card_sets, expr, actor, limit) do
    Sanctum.Catalog.CardSet
    |> base_query(expr)
    |> Ash.Query.sort(name: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.Query.load(:pack)
    |> Ash.read!(actor: actor)
  end

  defp do_fetch(:villains, expr, actor, limit) do
    Sanctum.Villains.Villain
    |> base_query(expr)
    |> Ash.Query.sort(villain_name: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.read!(actor: actor)
  end

  defp do_fetch(:scenarios, expr, actor, limit) do
    Sanctum.Games.Scenario
    |> base_query(expr)
    |> Ash.Query.sort(name: :asc)
    |> Ash.Query.limit(limit)
    |> Ash.read!(actor: actor)
  end

  defp base_query(resource, nil), do: Ash.Query.new(resource)
  defp base_query(resource, expr), do: Ash.Query.filter(Ash.Query.new(resource), ^expr)

  defp to_results(sides, :cards, _actor) do
    Enum.map(sides, fn side ->
      %{
        id: side.card_id,
        title: side.name,
        subtitle:
          join_subtitle([
            humanize(side.type),
            (side.card.pack_ref && side.card.pack_ref.name) || side.card.pack
          ]),
        href: "/cards/#{side.card_id}",
        kind: :card
      }
    end)
  end

  defp to_results(decks, :decks, _actor) do
    Enum.map(decks, fn deck ->
      %{
        id: deck.id,
        title: deck.title || "Untitled deck",
        subtitle: deck.hero && deck.hero.display_name,
        href: "/decks/#{deck.id}",
        kind: :deck
      }
    end)
  end

  defp to_results(heroes, :heroes, _actor) do
    Enum.map(heroes, fn hero ->
      %{
        id: hero.id,
        title: hero.display_name || hero.hero_name,
        subtitle: hero.alter_ego_name,
        href: "/decks?hero_id=#{hero.id}",
        kind: :hero
      }
    end)
  end

  defp to_results(packs, :packs, _actor) do
    Enum.map(packs, fn pack ->
      %{
        id: pack.id,
        title: pack.name || pack.code,
        subtitle: humanize(pack.product_type) || "Pack",
        href: "/browse/#{pack.code}",
        kind: :pack
      }
    end)
  end

  defp to_results(sets, :card_sets, _actor) do
    Enum.map(sets, fn set ->
      %{
        id: set.id,
        title: set.name || set.code,
        subtitle: join_subtitle([humanize(set.set_type), set.pack && set.pack.name]),
        href: set.pack && browse_href(set.pack.code, set.code),
        kind: :card_set
      }
    end)
  end

  defp to_results(villains, :villains, actor) do
    packs = pack_codes_by_set(Enum.map(villains, & &1.set), actor)

    Enum.map(villains, fn villain ->
      %{
        id: villain.id,
        title: villain.villain_name,
        subtitle: "Villain",
        href: browse_href(packs[villain.set], villain.set),
        kind: :villain
      }
    end)
  end

  defp to_results(scenarios, :scenarios, actor) do
    packs = pack_codes_by_set(Enum.map(scenarios, & &1.set), actor)

    Enum.map(scenarios, fn scenario ->
      %{
        id: scenario.id,
        title: scenario.name,
        subtitle: "Scenario",
        href: browse_href(packs[scenario.set], scenario.set),
        kind: :scenario
      }
    end)
  end

  # Villains and scenarios carry a `set` slug that matches `card_sets.code`;
  # resolve those to pack codes in one batch so results can link to the pack's
  # browse page. Unmatched sets simply yield link-less results.
  defp pack_codes_by_set([], _actor), do: %{}

  defp pack_codes_by_set(sets, actor) do
    codes = Enum.uniq(sets)

    Sanctum.Catalog.CardSet
    |> Ash.Query.filter(code in ^codes)
    |> Ash.Query.load(:pack)
    |> Ash.read!(actor: actor)
    |> Map.new(fn set -> {set.code, set.pack && set.pack.code} end)
  rescue
    error ->
      Logger.error(
        "global search pack resolution failed: #{Exception.format(:error, error, __STACKTRACE__)}"
      )

      %{}
  end

  # Set-scoped results land on the pack's browse page with the card-set code
  # as the fragment; the pack page renders set sections with matching DOM ids
  # and scrolls the fragment into view once its async load renders.
  defp browse_href(nil, _set_code), do: nil
  defp browse_href(pack_code, set_code), do: "/browse/#{pack_code}##{set_code}"

  defp more_url(:cards, rest), do: "/cards" <> query_param(rest)
  defp more_url(:decks, rest), do: "/decks" <> query_param(rest)
  defp more_url(_key, _rest), do: nil

  defp query_param(""), do: ""
  defp query_param(query), do: "?query=" <> URI.encode_www_form(query)

  defp join_subtitle(parts) do
    case Enum.reject(parts, &(&1 in [nil, ""])) do
      [] -> nil
      parts -> Enum.join(parts, " · ")
    end
  end

  defp humanize(nil), do: nil

  defp humanize(atom) when is_atom(atom) do
    atom
    |> to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
