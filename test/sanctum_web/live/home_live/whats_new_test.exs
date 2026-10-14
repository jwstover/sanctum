defmodule SanctumWeb.HomeLive.WhatsNewTest do
  @moduledoc false

  # Points the global :release_notes_dir config at a temp dir.
  use SanctumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    Application.put_env(:sanctum, :release_notes_dir, dir)
    on_exit(fn -> Application.delete_env(:sanctum, :release_notes_dir) end)
  end

  test "hides the What's New section when there are no notes", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/")

    refute html =~ "What&#39;s New"
    refute has_element?(view, "#whats-new")
  end

  test "shows the latest three notes, newest first", %{conn: conn, tmp_dir: dir} do
    for {tag, n} <- [{"v1.9.0", 9}, {"v1.10.0", 10}, {"v1.11.0", 11}, {"v1.100.0", 100}] do
      File.write!(Path.join(dir, "#{tag}.md"), "Date: 2026-10-01\n\n## New\n\n- Feature #{n}\n")
    end

    {:ok, view, _html} = live(conn, ~p"/")
    section = view |> element("#whats-new") |> render()

    assert section =~ "Oct 1, 2026"
    assert section =~ "<h2>New</h2>"
    assert section =~ "Feature 100"
    assert section =~ "Feature 11"
    assert section =~ "Feature 10"
    refute section =~ "Feature 9<"
    assert :binary.match(section, "v1.100.0") < :binary.match(section, "v1.10.0")
    assert has_element?(view, ~s(#whats-new a[href="/releases"]), "See all releases")
  end
end
