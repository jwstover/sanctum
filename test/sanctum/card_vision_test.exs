defmodule Sanctum.CardVisionTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Sanctum.CardVision

  @image_url "https://example.com/cards/custom-ally.png"

  defp stub_extraction(fields) do
    Req.Test.stub(CardVision, fn conn ->
      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [%{"type" => "text", "text" => Jason.encode!(fields)}]
      })
    end)
  end

  test "returns the extracted fields, pruning nulls and absent stats" do
    stub_extraction(%{
      "name" => "Test Ally",
      "subname" => nil,
      "type" => "ally",
      "ownership" => "player",
      "aspect" => "justice",
      "cost" => 2,
      "attack" => %{"value" => 1, "star" => false, "scaling" => "flat", "consequential" => 1},
      "thwart" => %{"value" => 2, "star" => true, "scaling" => "flat", "consequential" => 1},
      "defense" => %{"value" => nil, "star" => false, "scaling" => "flat", "consequential" => nil},
      "health" => %{"value" => 3, "star" => false, "scaling" => "flat", "consequential" => nil},
      "recover" => nil,
      "scheme" => nil,
      "scheme_star" => false,
      "traits" => ["Avenger"],
      "text" => "<b>Response</b>: After Test Ally enters play, draw 1 card.",
      "flavor" => nil
    })

    assert {:ok, fields} = CardVision.extract_side(@image_url)

    assert fields["name"] == "Test Ally"
    assert fields["aspect"] == "justice"
    assert fields["thwart"]["star"] == true
    assert fields["traits"] == ["Avenger"]

    # Nulls and value-less stats are pruned so applying never blanks a field.
    refute Map.has_key?(fields, "subname")
    refute Map.has_key?(fields, "defense")
    refute Map.has_key?(fields, "recover")
    refute Map.has_key?(fields, "flavor")
  end

  test "prunes sentinel values: 'none' enums, empty strings, zero consequential" do
    stub_extraction(%{
      "name" => "Breakin' & Takin'",
      "subname" => "",
      "type" => "treachery",
      "ownership" => "encounter",
      "aspect" => "none",
      "flavor" => "",
      "attack" => %{"value" => 2, "star" => false, "scaling" => "flat", "consequential" => 0}
    })

    assert {:ok, fields} = CardVision.extract_side(@image_url)

    assert fields["ownership"] == "encounter"
    refute Map.has_key?(fields, "aspect")
    refute Map.has_key?(fields, "subname")
    refute Map.has_key?(fields, "flavor")
    assert fields["attack"]["consequential"] == nil
  end

  test "drops a misread cost on card types that never have one" do
    # Encounter cards print health where player cards print cost — a model
    # slip there must not survive extraction.
    stub_extraction(%{
      "name" => "Hired Muscle",
      "type" => "minion",
      "ownership" => "encounter",
      "cost" => 4,
      "health" => %{"value" => 4, "star" => false, "scaling" => "flat", "consequential" => 0},
      "attack" => %{"value" => 2, "star" => false, "scaling" => "flat", "consequential" => 0},
      "scheme" => 1
    })

    assert {:ok, fields} = CardVision.extract_side(@image_url)

    refute Map.has_key?(fields, "cost")
    assert fields["health"]["value"] == 4
    assert fields["scheme"] == 1
  end

  # The API rejects schemas with more than 16 union-typed (anyOf/type-array)
  # parameters, counting nested object properties — a 400 we shipped once.
  test "request schema stays under the structured-outputs union limit" do
    parent = self()

    Req.Test.stub(CardVision, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(parent, {:request_body, body})

      Req.Test.json(conn, %{
        "stop_reason" => "end_turn",
        "content" => [%{"type" => "text", "text" => "{}"}]
      })
    end)

    assert {:ok, _fields} = CardVision.extract_side(@image_url)
    assert_received {:request_body, body}

    union_count = (body |> String.split("anyOf") |> length()) - 1
    assert union_count <= 16
    refute body =~ ~s("type":[)
  end

  test "pruned stat maps cast cleanly through the Stat type" do
    stub_extraction(%{
      "name" => "Test Ally",
      "attack" => %{
        "value" => 2,
        "star" => false,
        "scaling" => "per_player",
        "consequential" => nil
      }
    })

    assert {:ok, fields} = CardVision.extract_side(@image_url)

    assert {:ok, %Sanctum.Games.Stat{value: 2, scaling: :per_player}} =
             Sanctum.Games.Stat.cast_input(fields["attack"], [])
  end

  test "surfaces a refusal as an error" do
    Req.Test.stub(CardVision, fn conn ->
      Req.Test.json(conn, %{"stop_reason" => "refusal", "content" => []})
    end)

    log =
      capture_log(fn ->
        assert {:error, :refused} = CardVision.extract_side(@image_url)
      end)

    assert log =~ "CardVision extraction failed for #{@image_url}"
  end

  test "surfaces and logs API errors with status and message" do
    Req.Test.stub(CardVision, fn conn ->
      conn
      |> Plug.Conn.put_status(429)
      |> Req.Test.json(%{"error" => %{"message" => "rate limited"}})
    end)

    log =
      capture_log(fn ->
        assert {:error, {:api_error, 429, "rate limited"}} =
                 CardVision.extract_side(@image_url)
      end)

    assert log =~ "CardVision extraction failed for #{@image_url}"
    assert log =~ "rate limited"
  end
end
