defmodule Sanctum.CardVision do
  @moduledoc """
  Reads a card side's printed fields off its image using the Claude API
  (vision + structured outputs).

  `extract_side/1` takes the side's public image URL and returns the
  creator-editable fields that `CardSide.enrich` accepts, as a string-keyed
  map ready to pass through `Card.update_custom`'s `card_sides` argument.
  Fields the model couldn't read (or that don't exist on the card) are
  omitted rather than nil, so extraction only ever fills — it never blanks
  a value the creator already entered.

  Configuration (`config :sanctum, Sanctum.CardVision`):

    * `:api_key` — Anthropic API key (`ANTHROPIC_API_KEY`, set in runtime.exs)
    * `:req_options` — extra Req options merged into the request (tests
      inject a `Req.Test` plug here)
  """

  require Logger

  @api_url "https://api.anthropic.com/v1/messages"
  @model "claude-opus-4-8"
  @anthropic_version "2023-06-01"

  @type result :: {:ok, %{String.t() => term()}} | {:error, term()}

  @doc """
  Extracts the printed fields from one card face image.

  Returns `{:ok, fields}` with only the fields legible on the card, or
  `{:error, reason}` — `:missing_api_key`, `:refused`, `:truncated`,
  `{:api_error, status, message}`, `{:request_failed, exception}`, or
  `{:unexpected_response, body}`.
  """
  @spec extract_side(String.t()) :: result()
  def extract_side(image_url) when is_binary(image_url) do
    result =
      with {:ok, api_key} <- fetch_api_key() do
        [
          url: @api_url,
          headers: [
            {"x-api-key", api_key},
            {"anthropic-version", @anthropic_version}
          ],
          json: request_body(image_url),
          receive_timeout: 120_000
        ]
        |> Keyword.merge(config(:req_options, []))
        |> Req.post()
        |> handle_response()
      end

    case result do
      {:error, reason} ->
        Logger.error(
          "CardVision extraction failed for #{image_url}: " <>
            inspect(reason, limit: 50, printable_limit: 4096)
        )

      _ok ->
        :ok
    end

    result
  end

  defp request_body(image_url) do
    %{
      model: @model,
      max_tokens: 4096,
      system: system_prompt(),
      output_config: %{format: %{type: "json_schema", schema: schema()}},
      messages: [
        %{
          role: "user",
          content: [
            %{type: "image", source: %{type: "url", url: image_url}},
            %{
              type: "text",
              text:
                "Read this Marvel Champions card face and extract its printed fields. " <>
                  "Mark anything not printed on this face as absent per the field rules."
            }
          ]
        }
      ]
    }
  end

  # -- Response handling -------------------------------------------------------

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    case body do
      %{"stop_reason" => "refusal"} ->
        {:error, :refused}

      %{"stop_reason" => "max_tokens"} ->
        {:error, :truncated}

      %{"content" => content} when is_list(content) ->
        decode_content(content, body)

      _ ->
        {:error, {:unexpected_response, body}}
    end
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    message =
      case body do
        %{"error" => %{"message" => message}} -> message
        _ -> nil
      end

    {:error, {:api_error, status, message}}
  end

  defp handle_response({:error, exception}), do: {:error, {:request_failed, exception}}

  defp decode_content(content, body) do
    with %{"text" => text} <- Enum.find(content, &(&1["type"] == "text")),
         {:ok, fields} <- Jason.decode(text) do
      {:ok, prune(fields)}
    else
      _ -> {:error, {:unexpected_response, body}}
    end
  end

  # Drops absent fields — nulls, empty strings/lists, the "none" enum
  # sentinel, and stat objects with no printed value — so applying the result
  # never clears an already-entered field. Sentinels exist because structured
  # outputs cap union-typed (nullable) parameters at 16 per schema; strings
  # and enums signal absence in-band instead of via null.
  @enum_keys ~w(type ownership aspect)
  @stat_keys ~w(attack thwart defense health recover)

  # The only card types with a printed resource cost. Encounter cards put
  # their health in the same top-left spot a player card puts its cost, so a
  # misread cost on a costless type is dropped outright rather than trusted.
  @costed_types ~w(ally event support upgrade player_side_scheme)

  defp prune(fields) do
    fields
    |> Enum.reject(fn {key, value} -> empty?(key, value) end)
    |> Map.new(fn {key, value} -> {key, normalize(key, value)} end)
    |> drop_phantom_cost()
  end

  defp drop_phantom_cost(%{"type" => type} = fields) when type not in @costed_types,
    do: Map.delete(fields, "cost")

  defp drop_phantom_cost(fields), do: fields

  defp empty?(_key, nil), do: true
  defp empty?(_key, ""), do: true
  defp empty?(_key, []), do: true
  defp empty?(key, "none") when key in @enum_keys, do: true
  defp empty?(_key, %{"value" => nil}), do: true
  defp empty?(_key, _value), do: false

  # Consequential damage uses 0 as its "none" sentinel; the Stat type expects
  # nil for an ally cost that isn't printed.
  defp normalize(key, %{"consequential" => 0} = stat) when key in @stat_keys,
    do: Map.put(stat, "consequential", nil)

  defp normalize(_key, value), do: value

  # -- Schema -------------------------------------------------------------------
  #
  # Mirrors CardSide.enrich's accepted fields exactly — anything else would be
  # rejected by the action. Structured outputs require additionalProperties:
  # false and every property listed in required, and cap union-typed (nullable)
  # parameters at 16 per schema — so only cost, scheme, and the five stat
  # objects are anyOf-null (7 unions); strings use "" and enums a "none" value
  # to signal absence, both stripped by prune/1.

  defp schema do
    properties = %{
      name: %{type: "string", description: "The card's title."},
      subname: %{
        type: "string",
        description: "Smaller subtitle under the name. Empty string if none."
      },
      type: enum_schema(Sanctum.Games.CardType, "The printed type line."),
      ownership:
        enum_schema(
          Sanctum.Games.CardOwnership,
          "Which pool the card belongs to (see instructions)."
        ),
      aspect:
        enum_schema(
          Sanctum.Games.CardAspect,
          "Only for aspect player cards; \"none\" otherwise."
        ),
      cost:
        nullable(
          %{type: "integer"},
          "Top-left resource cost — playable player cards only; " <>
            "null for encounter/hero/alter-ego/resource cards, X, or no cost."
        ),
      attack: nullable(stat_schema(), "ATK stat."),
      thwart: nullable(stat_schema(), "THW stat."),
      defense: nullable(stat_schema(), "DEF stat."),
      health: nullable(stat_schema(), "Hit points."),
      recover: nullable(stat_schema(), "REC stat."),
      scheme: nullable(%{type: "integer"}, "A villain's or minion's SCH (scheme) stat value."),
      scheme_star: %{
        type: "boolean",
        description: "True when a star icon is printed next to the SCH stat."
      },
      traits: %{
        type: "array",
        items: %{type: "string"},
        description: "The bold trait line, one entry per trait, no trailing periods."
      },
      text: %{
        type: "string",
        description: "The rules text, transcribed per the conventions. Empty string if none."
      },
      flavor: %{
        type: "string",
        description: "Italic flavor text, without quote styling. Empty string if none."
      }
    }

    %{
      type: "object",
      additionalProperties: false,
      required: properties |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort(),
      properties: properties
    }
  end

  defp stat_schema do
    %{
      type: "object",
      additionalProperties: false,
      required: ["value", "star", "scaling", "consequential"],
      properties: %{
        value: %{
          type: "integer",
          description: "The printed number. A dash or X means the whole stat is null instead."
        },
        star: %{
          type: "boolean",
          description: "A star icon is printed beside this stat (star effect in the text)."
        },
        scaling: %{
          type: "string",
          enum: ["flat", "per_player", "per_group"],
          description: "per_player when the per-hero icon is printed beside the value."
        },
        consequential: %{
          type: "integer",
          description:
            "Ally consequential damage: the count of small star pips beside ATK/THW. " <>
              "0 when there are none or the card is not an ally."
        }
      }
    }
  end

  defp enum_schema(enum_module, description) do
    values = Enum.map(enum_module.values(), &to_string/1) ++ ["none"]
    %{type: "string", enum: values, description: description <> " \"none\" when not printed."}
  end

  defp nullable(schema, description) do
    %{anyOf: [schema, %{type: "null"}], description: description}
  end

  # -- Prompt -------------------------------------------------------------------

  defp system_prompt do
    """
    You read card faces from Marvel Champions: The Card Game and transcribe their
    printed fields exactly. You are given one face of one card. Extract only what
    is printed on this face. Never guess a value you cannot see. Mark absent,
    illegible, or not-applicable fields as absent: null for cost, scheme, and the
    stat objects; an empty string for subname/text/flavor; "none" for the
    type/ownership/aspect enums; 0 for consequential damage.

    Field guidance:

    - Identify the card type first (printed type line); it determines which fields
      exist. Player cards: ally, event, resource, support, upgrade, player_side_scheme.
      Identity cards: hero, alter_ego. Encounter cards: villain, minion, treachery,
      attachment, side_scheme, main_scheme, environment, obligation.
    - ownership: "player" for aspect-colored player cards, "basic" for gray basic
      player cards, "hero" for a hero's signature cards (their identity set icon),
      "encounter" for villain/encounter-set cards, "campaign" for campaign cards.
    - aspect: only for aspect player cards — red = aggression, yellow = justice,
      blue = leadership, green = protection, "'POOL" branding = pool. Null for
      basic, hero, and encounter cards.
    - cost: only ally, event, support, upgrade, and player_side_scheme cards have
      a cost, printed in the circle at the top-left. Hero, alter-ego, resource,
      and ALL encounter cards (villain, minion, treachery, attachment, side_scheme,
      main_scheme, environment, obligation) never have a cost — always null. The
      number in the red/orange circle — on allies and minions — is always health
      (HP), never a cost. Heroes, alter-egos, and villains print their health
      instead as small text at the very bottom border of the card. On heroes and
      alter-egos that bottom border also prints the hand size — do not mistake
      the hand-size number for health (hand size is not extracted).
    - Stats: ATK/THW/DEF/REC/HP printed values. A dash means the stat is absent
      (null). "star" is true when a star icon sits beside the stat. On allies, the
      small star pips beside ATK and THW are that stat's "consequential" damage
      count. Health "scaling" is "per_player" when the per-hero icon is printed
      beside the number (common on villains, minions, and side schemes).
    - scheme/scheme_star: a villain's or minion's SCH stat (not scheme cards'
      threat values — those are not extracted here).
    - traits: the bold trait line above the rules text (e.g. "AVENGER. SPY." →
      ["Avenger", "Spy"]).
    - text: transcribe the rules text using these conventions — resource and game
      icons as bracket tokens: [energy], [mental], [physical], [wild], [cost],
      [star], [boost], [crisis], [hazard], [acceleration], [amplify], [per_hero],
      [per_group], [unique]; bold with <b></b> (keywords, ability labels like
      "Response" and "Hero Action"); italics with <i></i>; references to traits
      as [[Trait]]; line breaks as newlines. Do not transcribe boost icons in the
      bottom-right boost bar — only icons inside the rules text.
    - flavor: the italic flavor quote, if any, without surrounding quote marks
      styling changes.
    """
  end

  # -- Config -------------------------------------------------------------------

  defp fetch_api_key do
    case config(:api_key, nil) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :missing_api_key}
    end
  end

  defp config(key, default) do
    :sanctum
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(key, default)
  end
end
