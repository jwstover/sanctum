defmodule SanctumWeb.ReleaseNotesLive.IndexTest do
  @moduledoc false

  # Points the global :release_notes_dir config at a temp dir.
  use SanctumWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    Application.put_env(:sanctum, :release_notes_dir, dir)
    on_exit(fn -> Application.delete_env(:sanctum, :release_notes_dir) end)
  end

  test "shows an empty state when there are no notes", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/releases")

    assert has_element?(view, "#release-notes-empty", "No releases yet")
    refute has_element?(view, "#release-notes")
  end

  test "lists every note, newest first", %{conn: conn, tmp_dir: dir} do
    for {tag, n} <- [{"v1.9.0", 9}, {"v1.10.0", 10}, {"v1.11.0", 11}, {"v1.100.0", 100}] do
      File.write!(Path.join(dir, "#{tag}.md"), "Date: 2026-10-01\n\n## Fixed\n\n- Fix #{n}\n")
    end

    {:ok, view, _html} = live(conn, ~p"/releases")
    list = view |> element("#release-notes") |> render()

    for n <- [9, 10, 11, 100], do: assert(list =~ "Fix #{n}<")
    assert list =~ "<h2>Fixed</h2>"
    assert :binary.match(list, "v1.100.0") < :binary.match(list, "v1.11.0")
    assert :binary.match(list, "v1.10.0") < :binary.match(list, "v1.9.0")
    refute has_element?(view, "#release-notes-empty")
  end

  test "highlights the Releases sidebar link", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/releases")

    assert has_element?(view, ~s(a.text-primary[href="/releases"]), "Releases")
  end
end
