defmodule Sanctum.Decks.Writeup do
  @moduledoc """
  Renders a deck's `description_md` (imported verbatim from MarvelCDB) into safe,
  themed HTML for display.

  MarvelCDB writeups are a messy blend of Markdown, raw inline HTML (`<center>`,
  styled `<span>`s), GFM tables, and BBCode-ish card links. Most are prose; a
  minority mix in entire hand-built HTML blocks (full `<div>`/`<table>` layouts,
  `<marquee>`, inline styles — "art" decklists). HTML blocks can't be rendered both
  faithfully *and* safely inside our own DOM, so `render/1` splits a writeup into
  ordered segments, each displayed one of two ways:

    * **`:inline`** (the common case, and the prose between/around HTML blocks) —
      themed HTML injected into our page. Rewrites MarvelCDB card links
      (`[Name](/card/30010)`) to our own `/cards/:id` pages (batched `Card`/`CardAlt`
      resolution; unresolved codes degrade to plain text), normalizes MarvelCDB's
      malformed "stat block" tables (`| Player Type: || Johnny` — a stray `||` that
      drops the value), then renders with `MDEx` (CommonMark + GFM) preserving inline
      HTML and sanitizes the output, stripping author inline `style`/`class` so our
      `.deck-writeup` CSS governs appearance. MarvelCDB `[energy]`-style icon tokens
      render as ChampionsIcons glyphs (`Sanctum.CardText.icon_span/1`).

    * **`:rich`** — a hand-built HTML block rendered into a **sandboxed iframe**
      `srcdoc` instead. The author's styles/layout/`<marquee>` are preserved
      (permissive sanitize keeps presentational tags/attrs, strips scripts), and
      the sandbox (no `allow-scripts`, no `allow-same-origin`) isolates it from our
      DOM, cookies, and origin. The frame carries its own restrictive CSP.

  Rendering happens at display time, so link resolution always reflects the
  current catalog and re-imports need no reprocessing.
  """

  require Ash.Query

  # Card links point at a code we resolve to one of our cards. Match both the
  # relative form MarvelCDB emits (`/card/30010`) and absolute marvelcdb.com URLs.
  @card_link_re ~r/\[([^\]]*)\]\((?:https?:\/\/(?:www\.)?marvelcdb\.com)?\/card\/([0-9A-Za-z-]+)\)/

  # Some writeups link cards with raw HTML anchors instead of Markdown:
  # `<a href="https://marvelcdb.com/card/41008">`. Only absolute marvelcdb.com
  # URLs appear in this form.
  @card_href_re ~r/href=(["'])https?:\/\/(?:www\.)?marvelcdb\.com\/card\/([0-9A-Za-z-]+)\/?\1/

  # A GFM delimiter row (e.g. `|-|-|`, `| :--- | ---: |`).
  @sep_re ~r/^\s*\|?[\s:|-]*-[\s:|-]*\|?\s*$/
  @table_row_re ~r/^\s*\|/

  @typedoc """
  One rendered piece of a writeup, in document order. `:inline` carries safe HTML
  to inject into the page; `:rich` carries a complete HTML document for a sandboxed
  iframe `srcdoc`.
  """
  @type segment ::
          %{kind: :inline, html: Phoenix.HTML.safe()}
          | %{kind: :rich, srcdoc: String.t()}

  @doc """
  Renders `description_md` into an ordered list of display segments.

  Prose writeups yield a single `:inline` segment. HTML-heavy ("art") writeups are
  split so each hand-built HTML block becomes an isolated `:rich` segment while the
  surrounding prose stays `:inline` and themed. Returns `nil` when the description
  is blank (so callers can show an empty state).
  """
  @spec render(String.t() | nil) :: [segment()] | nil
  def render(md) when is_binary(md) do
    case String.trim(md) do
      "" ->
        nil

      trimmed ->
        segments =
          if rich_html?(trimmed) do
            md |> segment() |> Enum.map(&render_segment/1) |> Enum.reject(&is_nil/1)
          else
            [%{kind: :inline, html: inline_html(md)}]
          end

        case segments do
          [] -> nil
          segs -> segs
        end
    end
  end

  def render(_), do: nil

  @doc """
  Renders `description_md` to sanitized, themed inline HTML only.

  Returns a `t:Phoenix.HTML.safe/0` tuple, or `nil` when blank. Prefer `render/1`,
  which also handles HTML-heavy writeups; this remains for callers that always
  want inline output.
  """
  @spec to_html(String.t() | nil) :: Phoenix.HTML.safe() | nil
  def to_html(md) when is_binary(md) do
    case String.trim(md) do
      "" -> nil
      _ -> inline_html(md)
    end
  end

  def to_html(_), do: nil

  defp render_segment({:md, text}) do
    {:safe, iodata} = html = inline_html(text)

    # A run that renders to nothing (e.g. only an HTML comment) is dropped so it
    # doesn't leave an empty themed block.
    if iodata |> IO.iodata_to_binary() |> String.trim() == "",
      do: nil,
      else: %{kind: :inline, html: html}
  end

  defp render_segment({:html, text}), do: %{kind: :rich, srcdoc: rich_srcdoc(text)}

  # sobelow_skip ["XSS.Raw"] — sanitized by MDEx (ammonia) in render_markdown/1;
  # render_icon_tokens/1 only injects CardText's own glyph spans afterwards.
  defp inline_html(md) do
    md
    |> normalize_newlines()
    |> rewrite_card_links()
    |> fix_tables()
    |> render_markdown()
    |> render_icon_tokens()
    |> Phoenix.HTML.raw()
  end

  defp normalize_newlines(md), do: String.replace(md, "\r\n", "\n")

  # Resolve every distinct card code once, then splice results back in. Resolved
  # codes become links to our card page. Unresolved Markdown links keep only the
  # link text (a relative `/card/…` would 404 here); unresolved HTML anchors keep
  # their absolute marvelcdb.com URL, which still works.
  defp rewrite_card_links(md) do
    codes =
      [@card_link_re, @card_href_re]
      |> Enum.flat_map(&Regex.scan(&1, md, capture: :all_but_first))
      |> Enum.map(fn [_, code] -> code end)
      |> Enum.uniq()

    ids = resolve_codes(codes)

    md
    |> then(
      &Regex.replace(@card_link_re, &1, fn _full, name, code ->
        case Map.get(ids, code) do
          nil -> name
          id -> "[#{name}](/cards/#{id})"
        end
      end)
    )
    |> then(
      &Regex.replace(@card_href_re, &1, fn full, quote, code ->
        case Map.get(ids, code) do
          nil -> full
          id -> "href=#{quote}/cards/#{id}#{quote}"
        end
      end)
    )
  end

  # code => card_id, from a single Card read (by base_code) plus a single CardAlt
  # read (reprints) for whatever the first read missed.
  defp resolve_codes([]), do: %{}

  defp resolve_codes(codes) do
    # authorize?: false bypasses the Card read policy that hides other users'
    # private homebrew, so this read must stay pinned to the official catalog.
    cards =
      Sanctum.Games.Card
      |> Ash.Query.filter(base_code in ^codes and origin == :official)
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

  # `[energy]`-style MarvelCDB icon tokens become ChampionsIcons glyphs. Runs
  # after sanitization — which strips author span classes — so the glyph spans
  # survive. Unknown bracketed text stays literal, and `:rich` iframe segments
  # are left alone (the sandboxed srcdoc doesn't load the ChampionsIcons font).
  defp render_icon_tokens(html) do
    Regex.replace(~r/\[([a-z_]+)\]/, html, fn full, token ->
      Sanctum.CardText.icon_span(token) || full
    end)
  end

  defp render_markdown(md) do
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

  # Block-level structural/presentational tags signal a hand-built HTML document
  # rather than prose with the occasional inline `<span>`/`<center>`. A handful of
  # them is enough to route to the isolated iframe.
  @rich_tag_re ~r/<\s*(div|table|tbody|thead|tr|td|th|marquee|font|section|article|iframe)\b/i

  defp rich_html?(md) do
    @rich_tag_re
    |> Regex.scan(md)
    |> length() >= 3
  end

  # Split a writeup into ordered `{:md, text}` / `{:html, text}` runs. Depth-scans
  # block-container tags: a run of raw HTML starts when one opens at depth 0 and
  # ends when it closes back to 0; everything else (prose, inline tags) is Markdown.
  # So a hand-built HTML block is isolated while the prose around it stays themed.
  @tag_re ~r/<!--.*?-->|<\/?[a-zA-Z][a-zA-Z0-9-]*\b[^>]*?>/s
  @container_tags ~w(div table thead tbody tfoot tr td th section article aside
                     header footer nav marquee form figure fieldset ul ol dl)

  defp segment(md) do
    {segs, type, buf, _depth} =
      @tag_re
      |> Regex.split(md, include_captures: true)
      |> Enum.with_index()
      |> Enum.reduce({[], :md, [], 0}, &segment_step/2)

    segs |> flush_segment(type, buf) |> Enum.reverse()
  end

  # Even indices are text between tags; odd indices are the matched tags/comments.
  defp segment_step({part, i}, {segs, type, buf, depth}) when rem(i, 2) == 0,
    do: {segs, type, [buf, part], depth}

  defp segment_step({part, _i}, {segs, type, buf, depth}) do
    if String.starts_with?(part, "<!--") do
      {segs, type, [buf, part], depth}
    else
      {name, closing?} = parse_tag(part)
      block? = name in @container_tags

      cond do
        block? and not closing? and depth == 0 ->
          {flush_segment(segs, type, buf), :html, [part], 1}

        block? and not closing? ->
          {segs, type, [buf, part], depth + 1}

        block? and closing? and depth <= 1 ->
          {flush_segment(segs, :html, [buf, part]), :md, [], 0}

        block? and closing? ->
          {segs, type, [buf, part], depth - 1}

        true ->
          {segs, type, [buf, part], depth}
      end
    end
  end

  defp flush_segment(segs, type, buf) do
    text = IO.iodata_to_binary(buf)
    if String.trim(text) == "", do: segs, else: [{type, text} | segs]
  end

  defp parse_tag(tag) do
    name =
      ~r/^<\/?\s*([a-zA-Z][a-zA-Z0-9-]*)/ |> Regex.run(tag) |> Enum.at(1) |> String.downcase()

    {name, String.starts_with?(tag, "</")}
  end

  # Render an HTML block as a complete, self-contained document for a sandboxed
  # iframe `srcdoc`. Card links are still resolved; the permissive sanitize keeps
  # presentational markup but strips scripts. Isolation (sandbox + the frame's own
  # CSP) is what makes keeping styles/marquees safe.
  defp rich_srcdoc(html) do
    body =
      html
      |> normalize_newlines()
      |> rewrite_card_links()
      |> MDEx.safe_html(sanitize: permissive_sanitize(), escape: [content: false])

    """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; style-src 'unsafe-inline'; font-src https: data:;">
    <base target="_blank">
    <style>
      html, body { margin: 0; }
      body { padding: 14px; background: #0b0b0d; color: #f4f1ea; font-family: Verdana, Arial, sans-serif; overflow-wrap: anywhere; }
      img { max-width: 100%; height: auto; }
      a { color: #dbcb36; }
      table { max-width: 100%; }
    </style>
    </head>
    <body>#{body}</body>
    </html>
    """
  end

  # Permissive whitelist for iframe-isolated content: keep presentational tags and
  # inline `style`, but ammonia still strips `<script>`/`<style>` content and any
  # tag outside the whitelist (iframe/object/embed/form unwrap to their contents).
  defp permissive_sanitize do
    Keyword.merge(MDEx.Document.default_sanitize_options(),
      add_tags: ["marquee", "font"],
      add_generic_attributes: ~w(style align valign color bgcolor width height border
           cellpadding cellspacing face size behavior direction scrollamount background)
    )
  end
end
