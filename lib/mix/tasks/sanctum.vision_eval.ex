defmodule Mix.Tasks.Sanctum.VisionEval do
  @shortdoc "Benchmarks vision models on card-field extraction"

  @moduledoc """
  Runs one or more vision models over official catalog cards and scores their
  `Sanctum.CardVision` extractions against the database ground truth.

      # Batch eval: seeded sample of official cards, per-field accuracy table
      mix sanctum.vision_eval --models anthropic,ollama:qwen3-vl:8b --sample 12

      # Single card, several models, disagreements flagged for manual review
      mix sanctum.vision_eval --card 01001a --models anthropic,ollama:qwen3-vl:8b

      # A raw image URL works too (e.g. a homebrew card — no ground truth column)
      mix sanctum.vision_eval --card https://…/card.png --models …

  Model specs: `anthropic[:model]`, `ollama:<model>` (local, port 11434), and
  `openrouter:<model>` (needs `OPENROUTER_API_KEY`). Batch mode writes a
  per-card mismatch report to `tmp/vision_eval/`.
  """

  use Mix.Task

  alias Sanctum.CardVision.Eval

  @requirements ["app.start"]

  @switches [models: :string, sample: :integer, seed: :integer, card: :string, out: :string]

  @impl true
  def run(argv) do
    Logger.configure(level: :info)
    {opts, _argv} = OptionParser.parse!(argv, strict: @switches)

    models =
      opts
      |> Keyword.get(:models, "anthropic")
      |> String.split(",", trim: true)
      |> Enum.map(fn spec ->
        case Eval.parse_model_spec(String.trim(spec)) do
          {:ok, model} -> model
          {:error, message} -> Mix.raise(message)
        end
      end)

    case Keyword.fetch(opts, :card) do
      {:ok, card} -> single_card(card, models)
      :error -> batch(models, opts)
    end
  end

  # -- Batch mode -----------------------------------------------------------------

  defp batch(models, opts) do
    sample = Keyword.get(opts, :sample, 12)
    seed = Keyword.get(opts, :seed, 1234)

    sides = Eval.sample_sides(sample, seed)

    if sides == [],
      do: Mix.raise("no official card sides with images found — run mix sanctum.sync_cards")

    items = Enum.map(sides, &%{image_url: &1.image_url, side: &1})

    Mix.shell().info(
      "Evaluating #{length(models)} model(s) on #{length(items)} official cards (seed #{seed})\n"
    )

    results =
      Enum.map(models, fn model ->
        Mix.shell().info("#{model.label} ")

        runs =
          model
          |> Eval.run_model(items, fn _ -> IO.write(".") end)
          |> Enum.map(fn run ->
            comparison =
              run.fields && Eval.compare(run.fields, Eval.expected_fields(run.item.side))

            Map.put(run, :comparison, comparison)
          end)

        IO.write("\n")
        %{model: model, runs: runs, score: Eval.score(runs)}
      end)

    print_batch_table(results)
    write_details(results, opts)
  end

  defp print_batch_table(results) do
    labels = Enum.map(results, & &1.model.label)

    field_rows =
      Enum.map(Eval.fields(), fn field ->
        [field | Enum.map(results, &percent_cell(&1.score.fields[field]))]
      end)

    summary_rows = [
      [
        "OVERALL"
        | Enum.map(results, &percent_cell(%{graded: &1.score.graded, matched: &1.score.matched}))
      ],
      ["errors" | Enum.map(results, &to_string(&1.score.errors))],
      ["avg latency" | Enum.map(results, &avg_latency(&1.runs))],
      ["avg in tokens" | Enum.map(results, &avg_tokens(&1.runs, :input))],
      ["avg out tokens" | Enum.map(results, &avg_tokens(&1.runs, :output))]
    ]

    Mix.shell().info("")
    print_table([["field" | labels]] ++ field_rows ++ [:rule] ++ summary_rows)
  end

  defp percent_cell(%{graded: 0}), do: "—"

  defp percent_cell(%{graded: graded, matched: matched}),
    do: "#{round(matched / graded * 100)}% (#{matched}/#{graded})"

  defp avg_latency(runs) do
    case Enum.reject(runs, & &1.error) do
      [] -> "—"
      ok -> "#{Float.round(Enum.sum_by(ok, & &1.ms) / length(ok) / 1000, 1)}s"
    end
  end

  defp avg_tokens(runs, side) do
    tokens = for %{meta: %{usage: usage}} <- runs, is_integer(usage[side]), do: usage[side]

    case tokens do
      [] -> "—"
      tokens -> to_string(div(Enum.sum(tokens), length(tokens)))
    end
  end

  defp write_details(results, opts) do
    path =
      Keyword.get_lazy(opts, :out, fn ->
        stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
        Path.join("tmp/vision_eval", "eval-#{stamp}.json")
      end)

    File.mkdir_p!(Path.dirname(path))

    details =
      Enum.map(results, fn %{model: model, runs: runs} ->
        %{
          model: model.label,
          cards:
            Enum.map(runs, fn run ->
              %{
                code: run.item.side.code,
                name: run.item.side.name,
                image_url: run.item.image_url,
                ms: run.ms,
                usage: run.meta && run.meta.usage,
                error: run.error && inspect(run.error),
                mismatches:
                  for {field, %{status: :mismatch} = result} <- run.comparison || %{},
                      into: %{} do
                    {field,
                     %{
                       expected: result.expected,
                       got: result.got,
                       similarity: result.similarity && Float.round(result.similarity, 3)
                     }}
                  end
              }
            end)
        }
      end)

    File.write!(path, Jason.encode!(details, pretty: true))
    Mix.shell().info("\nPer-card mismatch details: #{path}")
  end

  # -- Single-card mode --------------------------------------------------------------

  defp single_card(card, models) do
    case Eval.resolve_card(card) do
      {:error, message} ->
        Mix.raise(message)

      {:ok, %{image_url: image_url, side: side} = item} ->
        if side do
          Mix.shell().info("Card: #{side.code} — #{side.name} (#{side.type})")
        end

        Mix.shell().info("Image: #{image_url}\n")

        runs =
          Enum.map(models, fn model ->
            Mix.shell().info("running #{model.label}…")
            [run] = Eval.run_model(model, [item])
            Map.put(run, :model, model)
          end)

        truth = side && Eval.expected_fields(side)
        print_single_card_table(runs, truth)
        print_long_values(runs, truth)
        print_errors(runs)
    end
  end

  defp print_single_card_table(runs, truth) do
    labels = Enum.map(runs, & &1.model.label)
    header = ["field"] ++ if(truth, do: ["TRUTH"], else: []) ++ labels ++ [""]

    rows =
      Enum.map(Eval.fields(), fn field ->
        values = Enum.map(runs, &(&1.fields && Map.get(&1.fields, field)))
        truth_cells = if truth, do: [render_value(Map.get(truth, field))], else: []

        ["#{field}"] ++
          truth_cells ++
          Enum.map(values, &render_value/1) ++
          [flags(field, values, if(truth, do: Map.get(truth, field), else: :no_truth))]
      end)

    latency_row =
      ["latency"] ++
        if(truth, do: ["—"], else: []) ++
        Enum.map(runs, &"#{Float.round(&1.ms / 1000, 1)}s") ++ [""]

    Mix.shell().info("")
    print_table([header] ++ rows ++ [:rule, latency_row])
    Mix.shell().info("\n⚠ = models disagree · ✗ = differs from ground truth")
  end

  # Flags a row where the models disagree with each other, and (when ground
  # truth exists) where any model differs from it.
  defp flags(field, values, truth_value) do
    disagree? =
      case values do
        [first | rest] -> Enum.any?(rest, &(!Eval.equivalent?(field, first, &1)))
        _ -> false
      end

    wrong? =
      truth_value != :no_truth and Enum.any?(values, &(!Eval.equivalent?(field, &1, truth_value)))

    String.trim("#{if disagree?, do: "⚠"} #{if wrong?, do: "✗"}")
  end

  @doc false
  def render_value(nil), do: "—"
  def render_value(value) when is_binary(value), do: value
  def render_value(value) when is_list(value), do: Enum.join(value, ", ")

  def render_value(%{"value" => v} = stat) do
    star = if stat["star"], do: "★", else: ""
    scaling = if stat["scaling"] in [nil, "flat"], do: "", else: " #{stat["scaling"]}"
    con = if stat["consequential"], do: " con:#{stat["consequential"]}", else: ""
    "#{v}#{star}#{scaling}#{con}"
  end

  def render_value(value), do: to_string(value)

  # Full untruncated values for the prose fields whenever they were flagged.
  defp print_long_values(runs, truth) do
    ~w(text flavor traits)
    |> Enum.filter(fn field ->
      values = Enum.map(runs, &(&1.fields && Map.get(&1.fields, field)))
      flags(field, values, if(truth, do: Map.get(truth, field), else: :no_truth)) != ""
    end)
    |> Enum.each(&print_long_field(&1, runs, truth && {:truth, Map.get(truth, &1)}))
  end

  defp print_long_field(field, runs, truth) do
    Mix.shell().info("\n── #{field} ──")

    with {:truth, truth_value} <- truth do
      Mix.shell().info("TRUTH:\n#{render_value(truth_value)}\n")
    end

    Enum.each(runs, fn run ->
      Mix.shell().info(
        "#{run.model.label}:\n#{render_value(run.fields && Map.get(run.fields, field))}\n"
      )
    end)
  end

  defp print_errors(runs) do
    for %{error: error, model: model} when not is_nil(error) <- runs do
      Mix.shell().info("\n#{model.label} FAILED: #{inspect(error)}")
    end
  end

  # -- Table rendering ---------------------------------------------------------------

  @cell_width 34

  defp print_table(rows) do
    cell_rows = Enum.reject(rows, &(&1 == :rule))

    widths =
      cell_rows
      |> Enum.map(fn row -> Enum.map(row, &String.length(truncate(&1))) end)
      |> Enum.zip_with(&Enum.max/1)

    Enum.each(rows, fn
      :rule ->
        Mix.shell().info(Enum.map_join(widths, "─┼─", &String.duplicate("─", &1)))

      row ->
        line =
          row
          |> Enum.zip(widths)
          |> Enum.map_join(" │ ", fn {cell, width} ->
            String.pad_trailing(truncate(cell), width)
          end)

        Mix.shell().info(String.trim_trailing(line))
    end)
  end

  defp truncate(cell) do
    cell = cell |> to_string() |> String.replace("\n", "⏎")

    if String.length(cell) > @cell_width,
      do: String.slice(cell, 0, @cell_width - 1) <> "…",
      else: cell
  end
end
