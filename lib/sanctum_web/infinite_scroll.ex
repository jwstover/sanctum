defmodule SanctumWeb.InfiniteScroll do
  @moduledoc """
  Shared socket helpers for the infinite-scroll browse pages (card pool, deck
  browser): the viewport-triggered next-page load and the ScrollRestore-hook
  offset restoration.

  Callers own their data fetching through the `start_load` callback —
  `(socket, offset, opts) -> socket` with the same `:reset`/`:restore` opts
  the pages' local `start_load/3` already takes.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3]

  # Deepest infinite-scroll offset a scroll restore will refetch in one query
  # (limit = offset + page size must stay within Ash's 250 max page size).
  @max_restore_pages 9

  @doc """
  Handles the viewport next-page trigger, ignoring it while a page is already
  in flight so a burst of scroll events can't fan out into overlapping loads.
  """
  def next_page(socket, page_size, start_load) do
    if socket.assigns.end_of_timeline? or socket.assigns.loading? do
      socket
    else
      start_load.(socket, socket.assigns.offset + page_size, [])
    end
  end

  @doc """
  Handles the ScrollRestore hook's saved offset: refetch everything through
  the saved infinite-scroll offset in one query, then confirm so the hook can
  restore the scroll position.
  """
  def restore_scroll(socket, offset, page_size, start_load) do
    offset = sanitize_offset(offset, page_size)

    cond do
      offset > 0 ->
        socket
        |> assign(:scroll_restore_pending?, true)
        |> start_load.(offset, reset: true, restore: true)

      socket.assigns.loading? ->
        assign(socket, :scroll_restore_pending?, true)

      true ->
        confirm_scroll_restore(socket)
    end
  end

  @doc """
  Confirms a pending scroll restore to the ScrollRestore hook once the
  restored page has loaded; no-op when none is pending.
  """
  def maybe_confirm_scroll_restore(socket) do
    if socket.assigns.scroll_restore_pending?,
      do: confirm_scroll_restore(socket),
      else: socket
  end

  defp confirm_scroll_restore(socket) do
    socket
    |> assign(:scroll_restore_pending?, false)
    |> push_event("sanctum:scroll-restore", %{})
  end

  # Clamp a client-supplied offset to a sane page-aligned value.
  defp sanitize_offset(offset, page_size) when is_integer(offset) do
    offset
    |> max(0)
    |> min(page_size * @max_restore_pages)
    |> then(&(&1 - rem(&1, page_size)))
  end

  defp sanitize_offset(_, _), do: 0
end
