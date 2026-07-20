defmodule SanctumWeb.SearchHelpLive do
  @moduledoc """
  Reference page for the advanced search query language (`Sanctum.Search`).

  The field tables are generated from the live registries
  (`Sanctum.Search.CardFields` / `DeckFields`), so this page can never drift
  from what the language actually supports. Every example is a link that runs
  the query.
  """

  use SanctumWeb, :live_view

  alias Sanctum.Search.{CardFields, DeckFields, Field}

  @op_symbols [eq: ":", neq: "!=", lt: "<", gt: ">", lte: "<=", gte: ">="]

  @card_examples [
    {"spider", "cards whose name or subtitle contains “spider” — no syntax needed"},
    {"aspect:aggression cost<=2 type:ally", "cheap Aggression allies"},
    {"t:ally atk>=2 -trait:avenger", "hard-hitting allies that aren't Avengers"},
    {~s(x:"draw a card" a:justice|leadership), "card draw in Justice or Leadership"},
    {"is:unique hp>=10", "unique characters with 10+ health"},
    {"(t:minion or t:treachery) boost>=2", "encounter cards with big boost"}
  ]

  @deck_examples [
    {"hero:spider aspect:justice", "Justice decks for Spider-heroes"},
    {~s(card:"boot camp" cards>=40), "40+ card decks running Boot Camp"},
    {"aspect:basic", "decks with no aspect cards"}
  ]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash}>
      <.header>
        Search Syntax
        <:subtitle>
          The card pool and deck browser share a query language: type plain words to
          search names, or combine field filters for precise questions. Everything is
          case-insensitive, and partial or imperfect queries still return results.
        </:subtitle>
      </.header>

      <div class="max-w-4xl space-y-8">
        <section>
          <.section_title>Basics</.section_title>
          <div class="space-y-2.5 font-barlow text-[15px] leading-relaxed text-base-content/85">
            <p>
              A bare word like <.q c="spider" /> searches card names and subtitles
              (deck titles and heroes on the deck browser). Use <.q c={~s("quotes")} />
              for multi-word phrases.
            </p>
            <p>
              A filter is <span class="font-semibold">field, operator, value</span>:
              <.q c="cost<=2" /> or <.q c="aspect:justice" />. The <.q c=":" /> and <.q c="=" />
              operators both mean “equals”; numeric fields
              also take <.q c="!=" />, <.q c="<" />, <.q c=">" />, <.q c="<=" />, and
              <.q c=">=" />. Most fields have a short alias — <.q c="a:justice" /> is the same as
              <.q c="aspect:justice" />.
            </p>
            <p>
              Values can be shortened to any unambiguous prefix: <.q c="t:all" /> means
              <.q c="type:ally" />.
            </p>
          </div>
        </section>

        <section>
          <.section_title>Combining terms</.section_title>
          <table class="qh-table">
            <tbody>
              <tr>
                <td><.q c="a:justice cost<=2" /></td>
                <td>space between terms means AND (writing <.q c="and" /> also works)</td>
              </tr>
              <tr>
                <td><.q c="t:ally or t:event" /></td>
                <td><.q c="or" /> matches either side</td>
              </tr>
              <tr>
                <td><.q c="(t:ally or t:event) cost:1" /></td>
                <td>parentheses group</td>
              </tr>
              <tr>
                <td><.q c="-trait:avenger" /></td>
                <td>
                  a leading <.q c="-" /> (or the word <.q c="not" />) excludes matches
                </td>
              </tr>
              <tr>
                <td><.q c="a:justice|leadership" /></td>
                <td><.q c="|" /> tries several values for one field</td>
              </tr>
            </tbody>
          </table>
        </section>

        <section id="global">
          <.section_title>Global search</.section_title>
          <div class="space-y-2.5 font-barlow text-[15px] leading-relaxed text-base-content/85">
            <p>
              The search bar in the header (press <.q c="⌘K" /> anywhere) searches the whole
              site at once — cards, decks, heroes, packs, card sets, villains, and
              scenarios — with this same query language, grouped by type.
            </p>
            <p>
              Add <.q c="in:" /> to limit results to specific types:
              <.q c="in:decks spider" />, or several at once with <.q c="in:cards|decks" />. Types:
              <span :for={type <- @global_types} class="mr-1"><.q c={type} /></span>
            </p>
            <p>
              A typed filter also narrows the search on its own, to the types that
              understand it — <.q c="cost<=2" /> only ever matches cards, so only card
              results appear; <.q c="aspect:aggression" /> means both cards and decks.
            </p>
          </div>
        </section>

        <section id="cards">
          <.section_title>Card fields</.section_title>
          <.fields_table fields={@card_fields} base_path="/cards" />
        </section>

        <section id="decks">
          <.section_title>Deck fields</.section_title>
          <.fields_table fields={@deck_fields} base_path="/decks" />
        </section>

        <section>
          <.section_title>Example searches</.section_title>
          <table class="qh-table">
            <tbody>
              <tr :for={{query, description} <- @card_examples}>
                <td><.try_link query={query} base_path="/cards" /></td>
                <td>{description}</td>
              </tr>
              <tr :for={{query, description} <- @deck_examples}>
                <td><.try_link query={query} base_path="/decks" /></td>
                <td>{description} <span class="text-base-content/45">(decks)</span></td>
              </tr>
            </tbody>
          </table>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp section_title(assigns) do
    ~H"""
    <h2 class="mb-2.5 font-anton text-[19px] uppercase tracking-[0.05em] text-primary">
      {render_slot(@inner_block)}
    </h2>
    """
  end

  # An inline query snippet.
  defp q(assigns) do
    ~H"""
    <code class="whitespace-nowrap bg-base-300 px-1.5 py-0.5 font-mono text-[13px] text-base-content">{@c}</code>
    """
  end

  # A query snippet that links to the search it demonstrates.
  defp try_link(assigns) do
    ~H"""
    <.link
      navigate={"#{@base_path}?#{URI.encode_query(query: @query)}"}
      class="whitespace-nowrap bg-base-300 px-1.5 py-0.5 font-mono text-[13px] text-secondary underline decoration-secondary/40 underline-offset-2 hover:text-primary"
    >
      {@query}
    </.link>
    """
  end

  defp fields_table(assigns) do
    ~H"""
    <table class="qh-table">
      <thead>
        <tr>
          <th>Field</th>
          <th>Matches</th>
          <th>Operators</th>
          <th>Example</th>
        </tr>
      </thead>
      <tbody>
        <tr :for={field <- @fields}>
          <td>
            <span class="font-semibold text-base-content">{field.name}</span>
            <span :for={alias_name <- field.aliases} class="ml-1.5 text-base-content/50">
              {alias_name}
            </span>
          </td>
          <td class="!whitespace-normal">{matches(field)}</td>
          <td class="whitespace-nowrap font-mono text-[12.5px]">{ops(field)}</td>
          <td>
            <.try_link :if={field.example} query={field.example} base_path={@base_path} />
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Search Syntax")
      |> assign(:card_fields, CardFields.fields())
      |> assign(:deck_fields, DeckFields.fields())
      |> assign(:global_types, Sanctum.Search.Global.type_values())
      |> assign(:card_examples, @card_examples)
      |> assign(:deck_examples, @deck_examples)

    {:ok, socket}
  end

  # What a field matches against — enum values verbatim, or a description for
  # free-text/numeric fields (mentioning autocomplete when values come from
  # the catalog).
  defp matches(%Field{kind: kind, values: values}) when kind in [:enum, :flag, :boolean],
    do: Enum.join(values, ", ")

  defp matches(%Field{kind: :text, values_fun: nil, hint: hint}), do: hint || "any text"

  defp matches(%Field{kind: :text, hint: hint}),
    do: "#{hint || "any text"} — autocompletes from the catalog"

  defp matches(%Field{kind: :stat}), do: "number (the printed value)"
  defp matches(%Field{kind: :integer}), do: "number"

  defp ops(%Field{ops: ops}) do
    @op_symbols
    |> Enum.filter(fn {op, _symbol} -> op in ops end)
    |> Enum.map_join("  ", fn {_op, symbol} -> symbol end)
  end
end
