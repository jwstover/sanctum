defmodule Sanctum.CardSync.ServerTest do
  @moduledoc false

  # async: false — the server task hits the DB outside the test process (needs
  # the shared sandbox) and the Req stub must be visible to that task too.
  use Sanctum.DataCase, async: false

  alias Sanctum.CardSync.Server
  alias Sanctum.Games

  @entries [
    %{
      "code" => "01050",
      "name" => "Hulk",
      "type_code" => "ally",
      "faction_code" => "aggression",
      "pack_code" => "core",
      "imagesrc" => "/bundles/cards/01050.png"
    },
    %{
      "code" => "01001a",
      "name" => "Spider-Man",
      "type_code" => "hero",
      "pack_code" => "core",
      "imagesrc" => "/bundles/cards/01001a.png"
    },
    %{
      "code" => "01001b",
      "name" => "Peter Parker",
      "type_code" => "alter_ego",
      "pack_code" => "core",
      "imagesrc" => "/bundles/cards/01001b.png"
    }
  ]

  setup do
    # The sync task is not the test process, so route its requests through a
    # plug fun instead of a process-owned Req.Test stub. The slow response
    # keeps the run alive long enough to observe the :running state.
    original = Application.get_env(:sanctum, :marvel_cdb_req_options)

    Application.put_env(:sanctum, :marvel_cdb_req_options,
      plug: fn conn ->
        Process.sleep(100)
        Req.Test.json(conn, @entries)
      end
    )

    on_exit(fn -> Application.put_env(:sanctum, :marvel_cdb_req_options, original) end)

    Server.subscribe()
    :ok
  end

  test "runs a sync in a detached task and broadcasts progress" do
    assert :ok = Server.start_sync(images?: false)

    assert_receive {:card_sync, %{status: :running}}

    # Only one sync at a time
    assert {:error, :already_running} = Server.start_sync(images?: false)

    assert_receive {:card_sync, %{status: :done} = final}, 2_000
    assert final.data == %{synced: 2, failed: 0}
    assert final.failures == []
    assert %DateTime{} = final.finished_at

    # The detached task actually wrote through Ash
    assert Games.get_card_by_code!("01001").is_multi_sided

    # Status survives for late-mounting LiveViews
    assert %{status: :done} = Server.status()
  end

  test "refuses to mirror images without bucket credentials" do
    vars = ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3 BUCKET_NAME)
    original = Map.new(vars, &{&1, System.get_env(&1)})
    Enum.each(vars, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(original, fn
        {_var, nil} -> :ok
        {var, value} -> System.put_env(var, value)
      end)
    end)

    assert {:error, {:missing_env, missing}} = Server.start_sync([])
    assert "AWS_ACCESS_KEY_ID" in missing

    # Data-only syncs don't need credentials
    assert :ok = Server.start_sync(images?: false)
    assert_receive {:card_sync, %{status: :done}}, 2_000
  end
end
