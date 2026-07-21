defmodule Sanctum.CardText do
  @moduledoc """
  Renders MarvelCDB card markup (`text`, `flavor`, `back_text`) into safe HTML.

  MarvelCDB carries one markup format across every text-bearing field:

    * inline emphasis tags — only `<b>`, `<i>` and `<em>` ever appear;
    * `<hr />` section dividers;
    * `\\n` line breaks;
    * `[token]` icon codes (e.g. `[energy]`, `[per_hero]`, `[star]`);
    * `[[Trait]]` double-bracket trait references (e.g. `[[X-MEN]]`, `[[Aerial]]`).

  `to_html/1` whitelists the three emphasis tags, turns newlines into `<br>`,
  swaps icon tokens for ChampionsIcons glyphs, and renders traits in the Komika
  face. Everything else is HTML-escaped, so raw MarvelCDB HTML can never inject
  markup into the page.

  Tokens without a glyph in our ChampionsIcons font (`attack`/`thwart`/`defense`
  and the trait icons) fall back to their name in small caps rather than the raw
  `[bracketed]` code.
  """
  import Phoenix.HTML, only: [html_escape: 1, safe_to_string: 1]

  # token => {glyph, resource-color class | nil}. The glyph letters are the
  # ChampionsIcons cmap, verified against MarvelCDB's own icon CSS.
  @icons %{
    "energy" => {"E", "text-res-energy"},
    "mental" => {"M", "text-res-mental"},
    "physical" => {"P", "text-res-physical"},
    "wild" => {"W", "text-res-wild"},
    "cost" => {"D", nil},
    "star" => {"S", nil},
    "boost" => {"B", nil},
    "crisis" => {"C", nil},
    "hazard" => {"H", nil},
    "acceleration" => {"A", nil},
    "amplify" => {"F", nil},
    "per_hero" => {"G", nil},
    "per_group" => {"T", nil},
    "unique" => {"U", nil}
  }

  # Splits a line into whitelisted tags (`<b>`/`<i>`/`<em>` emphasis and the
  # `<hr />` divider), `[[Trait]]` references, icon tokens, and the plain text
  # between them (kept as captures so nothing is dropped). The double-bracket
  # alternative precedes the single-bracket one so `[[Trait]]` never gets
  # mis-split as two icon tokens. Tag matching tolerates whitespace and stray
  # self-closing forms (e.g. an empty `<b/>`).
  @segment ~r{(</?(?:b|i|em)\s*/?>|<hr\s*/?>|\[\[[^\]]+\]\]|\[[a-z_]+\])}i

  @hr ~r{^<hr}i
  @self_closing_emphasis ~r{^<(?:b|i|em)\s*/>$}i
  @emphasis ~r{^</?(?:b|i|em)>$}i
  @token ~r/^\[[a-z_]+\]$/
  @trait ~r/^\[\[(.+)\]\]$/

  @doc """
  The `token => {glyph, color class | nil}` map of ChampionsIcons tokens.
  Consumers outside card text (the deck writeup renderer, the description
  editor's icon picker) share this as the single source of truth.
  """
  def icons, do: @icons

  @doc """
  The ChampionsIcons `<span>` for `token`, or `nil` when the font has no
  glyph for it.
  """
  def icon_span(token) do
    case Map.fetch(@icons, token) do
      {:ok, {glyph, nil}} ->
        ~s(<span class="font-champions leading-none">#{glyph}</span>)

      {:ok, {glyph, color}} ->
        ~s(<span class="font-champions leading-none #{color}">#{glyph}</span>)

      :error ->
        nil
    end
  end

  @doc """
  Convert a MarvelCDB markup string into `{:safe, iodata}` for direct use in
  HEEx. Returns an empty safe value for `nil` or `""`.
  """
  def to_html(text) when text in [nil, ""], do: {:safe, []}

  def to_html(text) when is_binary(text) do
    iodata =
      text
      |> String.replace("\r\n", "\n")
      |> String.split("\n")
      |> Enum.map(&render_line/1)
      |> Enum.intersperse("<br>")

    {:safe, iodata}
  end

  defp render_line(line) do
    @segment
    |> Regex.split(line, include_captures: true, trim: true)
    |> Enum.map(&render_segment/1)
  end

  defp render_segment(segment) do
    cond do
      Regex.match?(@hr, segment) -> ~s(<hr class="my-2 border-neutral/60">)
      Regex.match?(@self_closing_emphasis, segment) -> ""
      Regex.match?(@emphasis, segment) -> String.downcase(segment)
      match = Regex.run(@trait, segment) -> render_trait(Enum.at(match, 1))
      Regex.match?(@token, segment) -> render_icon(String.slice(segment, 1..-2//1))
      true -> escape(segment)
    end
  end

  defp render_trait(name) do
    ~s(<span class="font-komika">#{escape(name)}</span>)
  end

  defp render_icon(name) do
    case icon_span(name) do
      nil ->
        # No glyph in ChampionsIcons for this token — show the name in small
        # caps rather than the raw `[bracket]` code.
        label = name |> String.replace("_", " ") |> escape()
        ~s(<span class="font-semibold uppercase tracking-wide">#{label}</span>)

      span ->
        span
    end
  end

  defp escape(text), do: text |> html_escape() |> safe_to_string()
end
