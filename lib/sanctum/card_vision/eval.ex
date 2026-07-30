defmodule Sanctum.CardVision.Eval do
  @moduledoc """
  Benchmarking harness for `Sanctum.CardVision` — runs one or more vision
  models over official catalog cards (whose `CardSide` rows are ground truth)
  and scores per-field extraction accuracy. Backs `mix sanctum.vision_eval`.

  Model specs (`parse_model_spec/1`):

    * `anthropic` / `anthropic:<model>` — the Claude API (production path)
    * `ollama:<model>` — a local Ollama server, e.g. `ollama:qwen3-vl:8b`
    * `openrouter:<model>` — OpenRouter, e.g. `openrouter:qwen/qwen3-vl-8b-instruct`
      (needs `OPENROUTER_API_KEY`)
  """

  require Ash.Query

  alias Sanctum.CardVision

  @ollama_base_url "http://localhost:11434/v1"
  @openrouter_base_url "https://openrouter.ai/api/v1"

  @scalar_fields ~w(name subname type ownership aspect cost scheme scheme_star)
  @stat_fields ~w(attack thwart defense health recover)
  @text_fields ~w(text flavor)
  @fields @scalar_fields ++ @stat_fields ++ ["traits"] ++ @text_fields

  @text_match_threshold 0.95

  def fields, do: @fields

  # -- Model specs ----------------------------------------------------------------

  @doc "Parses a `provider[:model]` spec into `%{label, opts}` for extract_side_meta."
  def parse_model_spec("anthropic"), do: parse_model_spec("anthropic:claude-sonnet-5")

  def parse_model_spec("anthropic:" <> model),
    do:
      {:ok,
       %{label: "anthropic:#{model}", concurrency: 4, opts: [provider: :anthropic, model: model]}}

  def parse_model_spec("ollama:" <> model) when model != "" do
    # reasoning_effort "none": hybrid-thinking models (qwen3-vl) otherwise
    # spend the whole completion budget reasoning and never emit the JSON.
    {:ok,
     %{
       label: "ollama:#{model}",
       concurrency: 1,
       opts: [
         provider: :openai,
         base_url: @ollama_base_url,
         model: model,
         reasoning_effort: "none"
       ]
     }}
  end

  def parse_model_spec("openrouter:" <> model) when model != "" do
    case System.get_env("OPENROUTER_API_KEY") do
      key when is_binary(key) and key != "" ->
        {:ok,
         %{
           label: "openrouter:#{model}",
           concurrency: 4,
           opts: [provider: :openai, base_url: @openrouter_base_url, model: model, api_key: key]
         }}

      _ ->
        {:error, "openrouter:#{model} needs OPENROUTER_API_KEY in the environment"}
    end
  end

  def parse_model_spec(spec), do: {:error, "unrecognized model spec #{inspect(spec)}"}

  # -- Card selection ---------------------------------------------------------------

  @doc "Seeded random sample of official card sides that have images."
  def sample_sides(count, seed) do
    :rand.seed(:exsss, {seed, seed, seed})

    official_sides_query()
    |> Ash.read!(authorize?: false)
    |> Enum.shuffle()
    |> Enum.take(count)
  end

  @doc """
  Resolves `--card` input: a full image URL (no ground truth), a side code, or
  a card code (its primary side).
  """
  def resolve_card("http" <> _ = url), do: {:ok, %{image_url: url, side: nil}}

  def resolve_card(code) do
    # Not restricted to official cards — homebrew codes resolve too; their DB
    # values (whatever the creator entered) still make a useful truth column.
    side =
      Sanctum.Games.CardSide
      |> Ash.Query.filter(code == ^code and not is_nil(image_url))
      |> Ash.Query.limit(1)
      |> Ash.read!(authorize?: false)
      |> List.first()

    side =
      side ||
        Sanctum.Games.Card
        |> Ash.Query.filter(code == ^code)
        |> Ash.Query.load(:primary_side)
        |> Ash.Query.limit(1)
        |> Ash.read!(authorize?: false)
        |> case do
          [%{primary_side: %{image_url: url} = primary}] when is_binary(url) -> primary
          _ -> nil
        end

    case side do
      nil -> {:error, "no card side with an image found for code #{inspect(code)}"}
      side -> {:ok, %{image_url: side.image_url, side: side}}
    end
  end

  defp official_sides_query do
    Sanctum.Games.CardSide
    |> Ash.Query.filter(not is_nil(image_url) and card.origin == :official)
  end

  # -- Extraction -------------------------------------------------------------------

  @doc "Runs one model over a list of `%{image_url, side}` items, timing each call."
  def run_model(model, items, progress_fun \\ fn _ -> :ok end) do
    items
    |> Task.async_stream(
      fn item ->
        {micros, result} =
          :timer.tc(fn -> CardVision.extract_side_meta(item.image_url, model.opts) end)

        progress_fun.(item)

        case result do
          {:ok, fields, meta} ->
            %{item: item, fields: fields, meta: meta, ms: div(micros, 1000), error: nil}

          {:error, reason} ->
            %{item: item, fields: nil, meta: nil, ms: div(micros, 1000), error: reason}
        end
      end,
      max_concurrency: model.concurrency,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, run} -> run end)
  end

  # -- Ground truth -------------------------------------------------------------------

  @doc """
  Renders a `CardSide` into the extraction's string-keyed shape, with the same
  absence semantics as `CardVision`'s pruning (absent fields omitted).
  """
  def expected_fields(side) do
    scalars = %{
      "name" => side.name,
      # The catalog sync sets subname = name on ~75% of official sides even
      # though no subtitle is printed — a model correctly reads that as absent.
      "subname" => if(side.subname == side.name, do: nil, else: presence(side.subname)),
      "type" => side.type && to_string(side.type),
      "ownership" => side.ownership && to_string(side.ownership),
      "aspect" => presence(side.aspect),
      "cost" => side.cost,
      "scheme" => side.scheme,
      "scheme_star" => side.scheme_star,
      "traits" => if(side.traits == [], do: nil, else: side.traits),
      "text" => presence(side.text),
      "flavor" => presence(side.flavor)
    }

    stats =
      Map.new(@stat_fields, fn field ->
        {field, side |> Map.fetch!(String.to_existing_atom(field)) |> stat_map()}
      end)

    scalars
    |> Map.merge(stats)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp presence(nil), do: nil
  defp presence(""), do: nil
  defp presence(value), do: value

  defp stat_map(%{value: nil}), do: nil
  defp stat_map(nil), do: nil

  defp stat_map(stat),
    do: %{
      "value" => stat.value,
      "star" => stat.star,
      "scaling" => to_string(stat.scaling),
      "consequential" => stat.consequential
    }

  # -- Comparison ---------------------------------------------------------------------

  @doc """
  Compares extracted fields to expected fields. Returns a map of field name to
  `%{status: :match | :mismatch | :skip, expected, got, similarity}` — `:skip`
  when the field is absent on both sides (nothing to grade).
  """
  def compare(got, expected) do
    Map.new(@fields, fn field ->
      {field, compare_field(field, Map.get(got, field), Map.get(expected, field))}
    end)
  end

  @doc """
  Whether two extracted values for a field agree under the same normalization
  the scoring uses (text similarity, stat/trait normalization, …). Used to
  flag model disagreements in single-card mode.
  """
  def equivalent?(field, a, b), do: compare_field(field, a, b).status != :mismatch

  defp compare_field(field, got, expected) do
    base = %{expected: expected, got: got, similarity: nil}

    cond do
      is_nil(got) and is_nil(expected) ->
        %{base | similarity: 1.0} |> Map.put(:status, :skip)

      # scheme_star/booleans: extraction always emits them; absent truth = false.
      field == "scheme_star" ->
        put_status(base, boolean(got) == boolean(expected))

      is_nil(got) or is_nil(expected) ->
        Map.put(base, :status, :mismatch)

      field in @text_fields ->
        similarity = String.jaro_distance(normalize_text(got), normalize_text(expected))

        %{base | similarity: similarity}
        |> Map.put(:status, if(similarity >= @text_match_threshold, do: :match, else: :mismatch))

      field == "traits" ->
        put_status(base, normalize_traits(got) == normalize_traits(expected))

      field in @stat_fields ->
        put_status(base, normalize_stat(got) == normalize_stat(expected))

      # Case-insensitive: cards print names in caps, the catalog in title case.
      field in ~w(name subname) ->
        put_status(
          base,
          String.downcase(normalize_text(got)) == String.downcase(normalize_text(expected))
        )

      true ->
        put_status(base, got == expected)
    end
  end

  defp put_status(base, true), do: Map.put(base, :status, :match)
  defp put_status(base, false), do: Map.put(base, :status, :mismatch)

  defp boolean(nil), do: false
  defp boolean(value), do: value

  defp normalize_traits(traits) when is_list(traits) do
    traits
    |> Enum.map(fn trait ->
      trait |> to_string() |> String.trim_trailing(".") |> String.downcase() |> String.trim()
    end)
    |> Enum.sort()
  end

  defp normalize_traits(other), do: other

  defp normalize_stat(%{} = stat) do
    %{
      value: stat["value"],
      star: boolean(stat["star"]),
      scaling: stat["scaling"] || "flat",
      consequential: stat["consequential"]
    }
  end

  defp normalize_stat(other), do: other

  defp normalize_text(text) do
    text
    |> to_string()
    |> String.replace(~r/[“”]/u, "\"")
    |> String.replace(~r/[‘’]/u, "'")
    |> String.replace(~r/[–—]/u, "-")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  # -- Scoring ------------------------------------------------------------------------

  @doc """
  Aggregates comparison maps for one model into per-field and overall accuracy:
  `%{fields: %{field => %{graded, matched}}, graded, matched, errors}`.
  """
  def score(runs_with_comparisons) do
    field_scores =
      Map.new(@fields, fn field ->
        graded =
          runs_with_comparisons
          |> Enum.map(&get_in(&1, [:comparison, field]))
          |> Enum.reject(&(is_nil(&1) or &1.status == :skip))

        {field, %{graded: length(graded), matched: Enum.count(graded, &(&1.status == :match))}}
      end)

    totals = Map.values(field_scores)

    %{
      fields: field_scores,
      graded: totals |> Enum.map(& &1.graded) |> Enum.sum(),
      matched: totals |> Enum.map(& &1.matched) |> Enum.sum(),
      errors: Enum.count(runs_with_comparisons, & &1.error)
    }
  end
end
