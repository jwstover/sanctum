defmodule Mix.Tasks.Sanctum.ScrapeDecklistPages do
  @shortdoc "Scrapes MarvelCDB decklist list pages for authors and like counts"

  @moduledoc """
  Scrapes MarvelCDB's `/decklists/find/{page}?sort={date|likes}` HTML list
  pages for decklist authors and like counts, and applies them to
  already-imported decks. Skips decklists not held locally.

      mix sanctum.scrape_decklist_pages                          # page 1, sort=date
      mix sanctum.scrape_decklist_pages --pages 50                # pages 1..50
      mix sanctum.scrape_decklist_pages --start 20 --pages 10      # pages 20..29
      mix sanctum.scrape_decklist_pages --sort likes --pages 5     # top-liked first
      mix sanctum.scrape_decklist_pages --pause-ms 5000            # slower pacing

  Stops early if a page reports no rows, or if `--start` has walked past
  MarvelCDB's last page. On a fetch error, re-run with `--start <page>` to
  resume where it left off.
  """

  use Mix.Task

  require Logger

  alias Sanctum.MarvelCdb.DecklistPages

  @requirements ["app.start"]

  @switches [
    pages: :integer,
    start: :integer,
    sort: :string,
    pause_ms: :integer
  ]

  @impl true
  def run(argv) do
    {opts, _argv} = OptionParser.parse!(argv, strict: @switches)

    pages = Keyword.get(opts, :pages, 1)
    start = Keyword.get(opts, :start, 1)
    sort = parse_sort(Keyword.get(opts, :sort, "date"))
    pause_ms = Keyword.get(opts, :pause_ms, 3000)

    page_numbers = start..(start + pages - 1)

    summary =
      Enum.reduce_while(page_numbers, %{rows: 0, matched: 0, updated_users: 0}, fn page, acc ->
        scrape_one(page, sort, acc, last_page?(page, page_numbers), pause_ms)
      end)

    Logger.info(
      "Done: #{summary.rows} row(s), #{summary.matched} matched, #{summary.updated_users} username(s) updated"
    )
  end

  defp scrape_one(page, sort, acc, last?, pause_ms) do
    case DecklistPages.scrape_page(page, sort) do
      {:ok, result} ->
        Logger.info(
          "page #{page}: #{result.rows} rows, #{result.matched} matched, #{result.updated_users} usernames"
        )

        acc = %{
          rows: acc.rows + result.rows,
          matched: acc.matched + result.matched,
          updated_users: acc.updated_users + result.updated_users
        }

        stop? = result.rows == 0 or (result.last_page && page >= result.last_page) or last?

        if stop? do
          {:halt, acc}
        else
          Process.sleep(pause_ms)
          {:cont, acc}
        end

      {:error, reason} ->
        Mix.raise(
          "Scrape failed on page #{page}: #{inspect(reason)}. Re-run with --start #{page} to resume."
        )
    end
  end

  defp last_page?(page, page_numbers), do: page == page_numbers.last

  defp parse_sort("date"), do: :date
  defp parse_sort("likes"), do: :likes

  defp parse_sort(other),
    do: Mix.raise("--sort must be \"date\" or \"likes\", got #{inspect(other)}")
end
