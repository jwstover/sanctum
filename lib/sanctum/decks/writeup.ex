defmodule Sanctum.Decks.Writeup do
  @moduledoc """
  Renders a deck's `description_md` (imported verbatim from MarvelCDB) into safe,
  themed HTML for display.

  MarvelCDB writeups are a messy blend of Markdown, raw inline HTML (`<center>`,
  styled `<span>`s), GFM tables, and BBCode-ish card links. This module:

    * rewrites MarvelCDB card links (`[Name](/card/30010)`) to our own
      `/cards/:id` pages, resolving the code through `Card`/`CardAlt` in a single
      batched pass; unresolved codes degrade to plain text.
    * normalizes MarvelCDB's characteristically malformed "stat block" tables
      (`| Player Type: || Johnny` — a stray `||` that pushes the value into a
      nonexistent third column).
    * renders with `MDEx` (CommonMark + GFM) preserving inline HTML, then
      sanitizes the output (safe tag/attribute whitelist, `rel` on links,
      http/https-only URLs) and strips author inline `style`/`class` so our
      `.deck-writeup` CSS governs appearance.

  Rendering happens at display time, so link resolution always reflects the
  current catalog and re-imports need no reprocessing.
  """

  require Ash.Query

  # Card links point at a code we resolve to one of our cards. Match both the
  # relative form MarvelCDB emits (`/card/30010`) and absolute marvelcdb.com URLs.
  @card_link_re ~r/\[([^\]]*)\]\((?:https?:\/\/(?:www\.)?marvelcdb\.com)?\/card\/([0-9A-Za-z-]+)\)/

  # A GFM delimiter row (e.g. `|-|-|`, `| :--- | ---: |`).
  @sep_re ~r/^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$/
  @table_row_re ~r/^\s*\|/

  @doc """
  Renders `description_md` to sanitized, themed HTML.

  Returns a `t:Phoenix.HTML.safe/0` tuple, or `nil` when the description is blank
  (so callers can show an empty state).
  """
  # sobelow_skip ["XSS.Raw"] — output is sanitized by MDEx (ammonia) in render/1.
  @spec to_html(String.t() | nil) :: Phoenix.HTML.safe() | nil
  def to_html(md) when is_binary(md) do
    case String.trim(md) do
      "" ->
        nil

      _ ->
        md
        |> normalize_newlines()
        |> rewrite_card_links()
        |> fix_tables()
        |> render()
        |> Phoenix.HTML.raw()
    end
  end

  def to_html(_), do: nil

  defp normalize_newlines(md), do: String.replace(md, "\r\n", "\n")

  # Resolve every distinct card code once, then splice results back in. Resolved
  # codes become links to our card page; unresolved ones keep only the link text.
  defp rewrite_card_links(md) do
    codes =
      @card_link_re
      |> Regex.scan(md, capture: :all_but_first)
      |> Enum.map(fn [_name, code] -> code end)
      |> Enum.uniq()

    ids = resolve_codes(codes)

    Regex.replace(@card_link_re, md, fn _full, name, code ->
      case Map.get(ids, code) do
        nil -> name
        id -> "[#{name}](/cards/#{id})"
      end
    end)
  end

  # code => card_id, from a single Card read (by base_code) plus a single CardAlt
  # read (reprints) for whatever the first read missed.
  defp resolve_codes([]), do: %{}

  defp resolve_codes(codes) do
    cards =
      Sanctum.Games.Card
      |> Ash.Query.filter(base_code in ^codes)
      |> Ash.read!(authorize?: false)
      |> Map.new(&{&1.base_code, &1.id})

    missing = Enum.reject(codes, &Map.has_key?(cards, &1))

    alts =
      case missing do
        [] ->
          %{}

        _ ->
          Sanctum.Games.CardAlt
          |> Ash.Query.filter(code in ^missing)
          |> Ash.read!(authorize?: false)
          |> Map.new(&{&1.code, &1.card_id})
      end

    Map.merge(alts, cards)
  end

  # MarvelCDB stat tables commonly carry a stray `||` in data rows that shoves the
  # value past the declared column count, so comrak silently drops it. Collapse
  # runs of pipes to one — but only in data rows, since the header's leading `||`
  # legitimately declares an empty label column.
  defp fix_tables(md) do
    lines = String.split(md, "\n")

    sep_idxs =
      for {line, i} <- Enum.with_index(lines),
          Regex.match?(@sep_re, line),
          String.contains?(line, "-"),
          into: MapSet.new(),
          do: i

    header_idxs = MapSet.new(sep_idxs, &(&1 - 1))

    lines
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {line, i} ->
      cond do
        MapSet.member?(sep_idxs, i) -> line
        MapSet.member?(header_idxs, i) -> line
        Regex.match?(@table_row_re, line) -> Regex.replace(~r/\|{2,}/, line, "|")
        true -> line
      end
    end)
  end

  defp render(md) do
    MDEx.to_html!(md,
      extension: [table: true, strikethrough: true, autolink: true, tasklist: true],
      render: [unsafe: true],
      sanitize:
        Keyword.merge(MDEx.Document.default_sanitize_options(),
          # Drop author inline styling so our theme wins.
          rm_tag_attributes: %{
            "span" => ["style", "class"],
            "div" => ["style", "class"],
            "pre" => ["style", "class"]
          }
        )
    )
  end
end
