defmodule Sanctum.MarvelCdb.DecklistPages do
  @moduledoc """
  Scrapes MarvelCDB's `/decklists/find/{page}?sort={date|likes}` HTML list
  pages for data the JSON API doesn't expose: each decklist's author
  (MarvelCDB has no public user endpoint) and social counts (likes,
  favorites, comments).

  Each page renders 12 decklists as `<div class="box">` blocks. Parsing works
  block by block so a row missing its author link can't accidentally borrow
  the next row's author.

  Ships dormant — nothing in the app calls this yet. The one-time backfill
  and the periodic refresh are separate follow-up work that will drive it in
  production.
  """

  require Ash.Query

  alias Sanctum.Decks
  alias Sanctum.Decks.Deck
  alias Sanctum.MarvelCdb

  @type row :: %{
          decklist_id: String.t(),
          like_count: non_neg_integer(),
          favorite_count: non_neg_integer(),
          comment_count: non_neg_integer(),
          user_id: pos_integer() | nil,
          username: String.t() | nil
        }

  @decklists_marker ~s(<div class="decklists">)
  @box_marker ~s(<div class="box">)
  @pagination_marker ~s(<ul class="pagination)

  @decklist_id_regex ~r{href="/decklist/view/(\d+)}
  @like_count_regex ~r{class="social-icon-like".*?<span class="num">(\d+)</span>}s
  @favorite_count_regex ~r{class="social-icon-favorite".*?<span class="num">(\d+)</span>}s
  @comment_count_regex ~r{class="social-icon-comment".*?<span class="num">(\d+)</span>}s
  @author_regex ~r{<a href="/user/profile/(\d+)/[^"]*" class="username[^"]*">(.*?)</a>}s
  @pagination_number_regex ~r{<a href="[^"]*">\s*(\d+)}

  # Decodes HTML entities in one pass over the original string, so an
  # already-escaped ampersand (`&amp;lt;`) decodes only its outer entity
  # (`&lt;`), never re-decoding what it reveals.
  @entity_regex ~r/&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);/i
  @named_entities %{"amp" => "&", "lt" => "<", "gt" => ">", "quot" => "\"", "apos" => "'"}

  @doc """
  Fetches and parses one list page.
  """
  @spec fetch(pos_integer(), :date | :likes) :: {:ok, map()} | {:error, term()}
  def fetch(page, sort) do
    with {:ok, html} <- MarvelCdb.get_decklist_page(page, sort) do
      {:ok, parse(html)}
    end
  end

  @doc """
  Parses one list page's HTML into `%{rows: [row], last_page: pos_integer() |
  nil}`. `last_page` is `nil` when the page carries no pagination controls at
  all (callers treat that as "don't continue past this page").
  """
  @spec parse(String.t()) :: %{rows: [row], last_page: pos_integer() | nil}
  def parse(html) when is_binary(html) do
    %{rows: parse_rows(html), last_page: parse_last_page(html)}
  end

  @doc """
  Writes scraped rows to the database.

  Decks are matched by `(mcdb_type: :decklist, mcdb_id)` and get
  `mcdb_like_count` / `mcdb_social_synced_at` set. Rows for decklists not
  held locally are skipped (silently — the by-date decklist sync is what
  imports them) and counted as `:unmatched`.

  Usernames are upserted only for authors of *matched* rows: those authors
  already exist as `McdbUser` rows via import, so this only fills in
  usernames for authors we already hold decks for, without minting rows for
  authors we don't.

  Favorite and comment counts are parsed but intentionally not persisted —
  only the like count is stored.
  """
  @spec apply_rows([row], keyword()) :: %{
          matched: non_neg_integer(),
          unmatched: non_neg_integer(),
          updated_users: non_neg_integer()
        }
  def apply_rows(rows, _opts \\ []) do
    deck_by_mcdb_id = load_decks(rows)
    synced_at = DateTime.utc_now() |> DateTime.truncate(:second)

    {matched_rows, unmatched_rows} =
      Enum.split_with(rows, &Map.has_key?(deck_by_mcdb_id, &1.decklist_id))

    Enum.each(matched_rows, &apply_social(&1, deck_by_mcdb_id, synced_at))
    updated_users = matched_rows |> upsert_authors() |> length()

    %{
      matched: length(matched_rows),
      unmatched: length(unmatched_rows),
      updated_users: updated_users
    }
  end

  @doc "Fetches, applies, and returns a compact summary. See `fetch/2` and `apply_rows/2`."
  @spec scrape_page(pos_integer(), :date | :likes) :: {:ok, map()} | {:error, term()}
  def scrape_page(page, sort) do
    with {:ok, %{rows: rows, last_page: last_page}} <- fetch(page, sort) do
      applied = apply_rows(rows)

      {:ok,
       %{
         rows: length(rows),
         matched: applied.matched,
         updated_users: applied.updated_users,
         last_page: last_page
       }}
    end
  end

  defp load_decks(rows) do
    ids = Enum.map(rows, & &1.decklist_id)

    Deck
    |> Ash.Query.filter(mcdb_type == :decklist and mcdb_id in ^ids)
    |> Ash.Query.select([:id, :mcdb_id, :updated_at])
    |> Ash.read!(authorize?: false)
    |> Map.new(&{&1.mcdb_id, &1})
  end

  defp apply_social(row, deck_by_mcdb_id, synced_at) do
    deck = Map.fetch!(deck_by_mcdb_id, row.decklist_id)

    Decks.set_deck_mcdb_social!(
      deck,
      %{mcdb_like_count: row.like_count, mcdb_social_synced_at: synced_at},
      authorize?: false
    )
  end

  defp upsert_authors(matched_rows) do
    matched_rows
    |> Enum.filter(&(&1.user_id && &1.username))
    |> Enum.uniq_by(& &1.user_id)
    |> Enum.map(fn row ->
      Decks.upsert_mcdb_username!(
        %{mcdb_user_id: row.user_id, username: row.username},
        authorize?: false
      )
    end)
  end

  defp parse_rows(html) do
    case String.split(html, @decklists_marker, parts: 2) do
      [_no_decklists_section] -> []
      [_before, rest] -> rest |> scope_to_boxes() |> split_boxes() |> Enum.map(&parse_box/1)
    end
  end

  # Cuts off the trailing pagination + footer so a stray box-shaped fragment
  # in the footer can never be mistaken for a decklist.
  defp scope_to_boxes(rest) do
    case String.split(rest, @pagination_marker, parts: 2) do
      [scoped] -> scoped
      [scoped, _after] -> scoped
    end
  end

  defp split_boxes(scoped) do
    scoped
    |> String.split(@box_marker)
    # The chunk before the first box is whitespace between the section
    # opener and the first `<div class="box">`.
    |> Enum.drop(1)
    |> Enum.filter(&Regex.match?(@decklist_id_regex, &1))
  end

  defp parse_box(block) do
    [_, decklist_id] = Regex.run(@decklist_id_regex, block)
    {user_id, username} = parse_author(block)

    %{
      decklist_id: decklist_id,
      like_count: parse_count(@like_count_regex, block),
      favorite_count: parse_count(@favorite_count_regex, block),
      comment_count: parse_count(@comment_count_regex, block),
      user_id: user_id,
      username: username
    }
  end

  defp parse_count(regex, block) do
    case Regex.run(regex, block) do
      [_, count] -> String.to_integer(count)
      nil -> 0
    end
  end

  defp parse_author(block) do
    case Regex.run(@author_regex, block) do
      [_, user_id, username] ->
        {String.to_integer(user_id), username |> String.trim() |> decode_entities()}

      nil ->
        {nil, nil}
    end
  end

  # Reads only the FIRST pagination block's link-text numbers — an
  # out-of-range page still 200s with a pagination whose `&laquo;`/`&raquo;`
  # hrefs point past the real last page, so hrefs can't be trusted; the link
  # text (the page numbers users see) always tops out at the real last page.
  defp parse_last_page(html) do
    case String.split(html, @pagination_marker, parts: 2) do
      [_no_pagination] ->
        nil

      [_before, rest] ->
        rest
        |> String.split("</ul>", parts: 2)
        |> hd()
        |> pagination_max()
    end
  end

  defp pagination_max(segment) do
    case Regex.scan(@pagination_number_regex, segment) do
      [] -> nil
      matches -> matches |> Enum.map(fn [_, n] -> String.to_integer(n) end) |> Enum.max()
    end
  end

  defp decode_entities(string), do: Regex.replace(@entity_regex, string, &decode_entity/2)

  defp decode_entity(_match, "#" <> rest), do: decode_numeric_entity(rest)
  defp decode_entity(match, name), do: Map.get(@named_entities, String.downcase(name), match)

  defp decode_numeric_entity("x" <> hex), do: numeric_char(hex, 16, "&#x#{hex};")
  defp decode_numeric_entity(dec), do: numeric_char(dec, 10, "&##{dec};")

  defp numeric_char(digits, base, fallback) do
    case Integer.parse(digits, base) do
      {code, ""} -> <<code::utf8>>
      _ -> fallback
    end
  end
end
