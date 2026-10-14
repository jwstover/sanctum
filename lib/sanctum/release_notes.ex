defmodule Sanctum.ReleaseNotes do
  @moduledoc """
  Reads the committed, player-facing release notes in `priv/release_notes/*.md`.

  Each file is named for its release tag (`v1.84.0.md`). The first line is
  `Date: YYYY-MM-DD`, then a blank line, then a Markdown body. Notes are read at
  request time; files that don't fit the format are skipped (and logged) so one
  bad file can't break the homepage.

  The directory resolves through the release's own `priv/` (`Application.app_dir/2`)
  so it works inside a compiled OTP release, not just from the project root.
  Tests point `:sanctum, :release_notes_dir` at a temp dir instead.
  """

  require Logger

  @type note :: %{
          tag: String.t(),
          version: Version.t(),
          date: Date.t(),
          body_md: String.t()
        }

  @doc "Release notes, newest version first; `limit` caps how many are returned."
  @spec list(pos_integer() | nil) :: [note()]
  def list(limit \\ nil) do
    notes =
      notes_dir()
      |> Path.join("*.md")
      |> Path.wildcard()
      |> Enum.map(&parse_file/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort_by(& &1.version, {:desc, Version})

    if limit, do: Enum.take(notes, limit), else: notes
  end

  @doc "Renders a note's Markdown body to sanitized HTML."
  @spec to_html(note()) :: Phoenix.HTML.safe()
  # sobelow_skip ["XSS.Raw"] — sanitized by MDEx (ammonia) before marking safe.
  def to_html(%{body_md: md}) do
    md
    |> MDEx.to_html!(sanitize: MDEx.Document.default_sanitize_options())
    |> Phoenix.HTML.raw()
  end

  defp notes_dir do
    Application.get_env(:sanctum, :release_notes_dir) ||
      Application.app_dir(:sanctum, "priv/release_notes")
  end

  defp parse_file(path) do
    tag = Path.basename(path, ".md")

    with {:ok, version} <- Version.parse(String.trim_leading(tag, "v")),
         {:ok, contents} <- File.read(path),
         [header, body] <- String.split(contents, ~r/\R\R/, parts: 2),
         [_, date] <- Regex.run(~r/^Date:\s*(\d{4}-\d{2}-\d{2})\s*$/, header),
         {:ok, date} <- Date.from_iso8601(date) do
      %{tag: tag, version: version, date: date, body_md: String.trim(body)}
    else
      _ ->
        Logger.warning("Skipping malformed release note: #{path}")
        nil
    end
  end
end
