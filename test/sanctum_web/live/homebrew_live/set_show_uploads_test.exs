defmodule SanctumWeb.HomebrewLive.SetShowUploadsTest do
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

    set =
      Homebrew.create_set!(%{homebrew_project_id: project.id, name: "Kingpin"}, actor: creator)

    %{conn: log_in_user(conn, creator), path: ~p"/homebrew/#{project.id}/sets/#{set.id}"}
  end

  test "the Upload button opens the shape chooser (Card / Alt art)", ctx do
    {:ok, lv, _html} = live(ctx.conn, ctx.path)

    assert has_element?(lv, "button[phx-click='open_chooser']")

    html = lv |> element("button[phx-click='open_chooser']") |> render_click()

    # The chooser is one surface with both upload affordances — each a label
    # wrapping its file input, so choosing opens the picker in the same click.
    assert html =~ "What are you adding?"
    assert html =~ "Card"
    assert html =~ "Alt art"
    assert has_element?(lv, "#homebrew-uploads label input[type='file'][name='card_images']")
    assert has_element?(lv, "#homebrew-uploads label input[type='file'][name='alt_images']")
  end
end
