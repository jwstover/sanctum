defmodule SanctumWeb.InfiniteScroll do
  @moduledoc """
  Shared socket helpers for the infinite-scroll browse pages (card pool, deck
  browser): the viewport-triggered next-page load and the ScrollRestore-hook
  offset restoration.

  Callers own their data fetching through the `start_load` callback —
  `(socket, offset, opts) -> socket` with the same `:reset`/`:restore` opts
  the pages' local `start_load/3` already takes.
  """

  require Ash.Query

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_event: 3, stream: 4]

  alias Sanctum.Search.FormSync

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

  @doc """
  Assign the unfiltered catalog `:total` (the "/ N" denominator). `nil` means
  this load didn't refetch it — only the first/reset load does — so the
  existing total is left untouched. It must be computed independently of the
  visible page: deriving it from a filtered load's count breaks whenever that
  load already carries a query (e.g. arriving from global search).
  """
  def assign_total(socket, nil), do: socket
  def assign_total(socket, total), do: assign(socket, :total, total)

  @doc """
  Assign the filtered visible `:count` on reset loads only — `page.count` is
  queried just on resets (`count: reset?`), so non-reset (scroll) loads keep
  the prior count.
  """
  def assign_count(socket, false, _count), do: socket
  def assign_count(socket, true, count), do: assign(socket, :count, count)

  @doc """
  Resolves a `start_load/3` call's opts into `{query_offset, limit, reset?}`.
  `restore: true` refetches pages 0..offset in one query (for scroll
  restoration) while `offset` stays the logical last-page offset.
  """
  def load_opts(offset, page_size, opts) do
    reset? = Keyword.get(opts, :reset, false)
    restore? = Keyword.get(opts, :restore, false)
    {query_offset, limit} = if restore?, do: {0, offset + page_size}, else: {offset, page_size}
    {query_offset, limit, reset?}
  end

  @doc """
  Reads one page of a resource's `:browse` action for the window from
  `load_opts/3`, with `extra_loads` on top of what the action already loads.
  """
  def read_page(resource, args, actor, {query_offset, limit, reset?}, extra_loads \\ []) do
    resource
    |> Ash.Query.for_read(:browse, args, actor: actor)
    |> Ash.Query.load(extra_loads)
    |> Ash.read!(page: [limit: limit, offset: query_offset, count: reset?])
  end

  @doc "Full unfiltered size of a resource's `:browse` set (the \"/ N\" denominator)."
  def count_all(resource, actor) do
    resource
    |> Ash.Query.for_read(:browse, %{}, actor: actor)
    |> Ash.count!()
  end

  @doc """
  Applies an async page result to the socket: assigns offset, end-of-feed,
  total and count, and streams the rows through `to_view`. A result from a
  superseded request (`req` behind `req_id`) is dropped so out-of-order
  completions can't clobber the current view.
  """
  def put_page(socket, stream_name, result, to_view) do
    %{req: req, offset: offset, reset?: reset?, page: page, total: total} = result

    if req == socket.assigns.req_id do
      socket
      |> assign(:offset, offset)
      |> assign(:end_of_timeline?, !page.more?)
      |> assign(:loading?, false)
      |> assign_total(total)
      |> assign_count(reset?, page.count)
      |> stream(stream_name, Enum.map(page.results, to_view), reset: reset?)
      |> maybe_confirm_scroll_restore()
    else
      socket
    end
  end

  @doc """
  The `[query:, sort:]` URL params for a browse page, dropping an empty query
  and the default sort so the canonical URL stays bare.
  """
  def browse_params(query, sort, default_sort) do
    Enum.reject([query: query, sort: sort], fn
      {:query, v} -> v == ""
      {:sort, v} -> v == default_sort
    end)
  end

  @doc """
  A filter-sheet change: splices the submitted controls back into the query
  string and picks the sidecar sort radio (falling back to `current_sort`).
  Returns `{query, sort}`.
  """
  def sheet_change(params, query, registry, sort_keys, current_sort) do
    fields = FormSync.fields_from_params(params, registry)
    query = FormSync.update(query, registry, fields)
    sort = if params["sort"] in sort_keys, do: params["sort"], else: current_sort
    {query, sort}
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
