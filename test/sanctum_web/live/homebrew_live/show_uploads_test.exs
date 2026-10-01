defmodule SanctumWeb.HomebrewLive.ShowUploadsTest do
  @moduledoc false

  # Sets the S3 env vars `HomebrewImages.configured?/0` reads. They are global,
  # so this can't run alongside the async suite.
  use SanctumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanctum.AccountsFixtures

  alias Sanctum.Homebrew

  @s3_env_vars ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_ENDPOINT_URL_S3 BUCKET_NAME)

  setup %{conn: conn} do
    original = Map.new(@s3_env_vars, &{&1, System.get_env(&1)})
    Enum.each(@s3_env_vars, &System.put_env(&1, "test"))

    on_exit(fn ->
      Enum.each(original, fn
        {var, nil} -> System.delete_env(var)
        {var, value} -> System.put_env(var, value)
      end)
    end)

    creator = admin_user_fixture()
    project = Homebrew.create_project!(%{name: "Test Pack", attestation: true}, actor: creator)
    %{conn: log_in_user(conn, creator), project: project}
  end

  test "the Upload button opens the type chooser (Cards / Alt art)", ctx do
    {:ok, lv, _html} = live(ctx.conn, ~p"/homebrew/#{ctx.project.id}")

    assert has_element?(lv, "button[phx-click='open_chooser']")

    html = lv |> element("button[phx-click='open_chooser']") |> render_click()

    # The chooser is one surface with both upload affordances (labels wrapping
    # the file inputs); no separate upload pages.
    assert html =~ "What are you adding?"
    assert html =~ "Cards"
    assert html =~ "Alt art"
    assert has_element?(lv, "#homebrew-uploads")
  end
end
