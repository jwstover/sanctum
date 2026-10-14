defmodule Sanctum.ReleaseNotesTest do
  @moduledoc false

  # Points the global :release_notes_dir config at a temp dir.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Sanctum.ReleaseNotes

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    Application.put_env(:sanctum, :release_notes_dir, dir)
    on_exit(fn -> Application.delete_env(:sanctum, :release_notes_dir) end)
  end

  defp write_note(dir, tag, contents), do: File.write!(Path.join(dir, "#{tag}.md"), contents)

  test "an empty directory has no notes" do
    assert ReleaseNotes.list() == []
  end

  test "parses the Date line and the body", %{tmp_dir: dir} do
    write_note(dir, "v1.84.0", "Date: 2026-10-01\n\n## New\n\n- Deck charts\n")

    assert [note] = ReleaseNotes.list()
    assert note.tag == "v1.84.0"
    assert note.version == Version.parse!("1.84.0")
    assert note.date == ~D[2026-10-01]
    assert note.body_md == "## New\n\n- Deck charts"
  end

  test "sorts by version, not as strings, and honors the limit", %{tmp_dir: dir} do
    for tag <- ~w(v1.9.0 v1.100.0 v1.10.0 v1.99.0) do
      write_note(dir, tag, "Date: 2026-10-01\n\nBody")
    end

    assert Enum.map(ReleaseNotes.list(), & &1.tag) == ~w(v1.100.0 v1.99.0 v1.10.0 v1.9.0)
    assert Enum.map(ReleaseNotes.list(2), & &1.tag) == ~w(v1.100.0 v1.99.0)
  end

  test "skips malformed files instead of raising", %{tmp_dir: dir} do
    write_note(dir, "v1.1.0", "Date: 2026-10-01\n\nGood")
    write_note(dir, "v1.2.0", "## New\n\n- No date line")
    write_note(dir, "v1.3.0", "Date: 2026-13-45\n\nBad date")
    write_note(dir, "not-a-version", "Date: 2026-10-01\n\nBad tag")

    log = capture_log(fn -> assert [%{tag: "v1.1.0"}] = ReleaseNotes.list() end)
    assert log =~ "Skipping malformed release note"
  end

  test "to_html renders Markdown and strips scripts" do
    html =
      %{body_md: "## Fixed\n\n- **Bold** fix\n\n<script>alert(1)</script>"}
      |> ReleaseNotes.to_html()
      |> Phoenix.HTML.safe_to_string()

    assert html =~ "<h2>Fixed</h2>"
    assert html =~ "<strong>Bold</strong>"
    refute html =~ "<script>"
  end
end
