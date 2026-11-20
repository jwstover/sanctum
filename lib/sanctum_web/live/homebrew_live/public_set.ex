defmodule SanctumWeb.HomebrewLive.PublicSet do
  @moduledoc """
  The shareable, read-only page of a homebrew set at
  `/custom/@username/slug`. Slugs are unique per creator, so the creator's
  handle + slug resolve to exactly one set (`Homebrew.get_set_by_creator_slug/3`).

  This is the share-link surface: the dedicated `:by_creator_slug` /
  `Card :for_shared_set` reads let anyone holding the link see a published
  or unlisted set and its cards, while a private set resolves only for its
  creator. Unlisted sets stay out of every listing — only this page reaches
  them. Anything that doesn't resolve — unknown or
  renamed username, unknown slug, a set the viewer may not see — raises the
  Ash not-found error, which ash_phoenix maps to an ordinary 404.

  Contents are grouped by set: the set's own cards first, then one section
  per *published* descendant set (`:published_descendants`) in tree order.
  A published grandchild under a non-published child is listed flat rather
  than dropped. The page carries the unofficial-fan-content label.

  Signed-in visitors can report the set (`Homebrew.report_set/2`), which
  files it into the admin moderation queue (`AdminLive.Reports`); anonymous
  visitors are sent to sign in first.
  """

  use SanctumWeb, :live_view

  import SanctumWeb.Components.CardSection
  import SanctumWeb.Components.CardSideTile, only: [side_view: 2]
  import SanctumWeb.HomebrewComponents

  alias Sanctum.Games
  alias Sanctum.Homebrew
  alias SanctumWeb.HomebrewLive.Support

  on_mount {SanctumWeb.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(%{"username" => username, "slug" => slug}, _session, socket) do
    actor = socket.assigns[:current_user]

    set =
      Homebrew.get_set_by_creator_slug!(username, slug,
        actor: actor,
        load: [:set_kind, :creator]
      )

    hero_colors = Sanctum.Heroes.hero_color_map()

    own_cards =
      username
      |> Games.list_shared_set_cards!(slug, actor: actor)
      |> Enum.map(&card_view(&1, &1.shared_primary_side, hero_colors))

    {:ok,
     socket
     |> assign(:page_title, set.name)
     |> assign(:set, set)
     |> assign(:card_tiles, own_cards)
     |> assign(:child_groups, child_groups(set, actor, hero_colors))
     |> assign(:reporting?, false)
     |> assign(:reported?, false)}
  end

  @impl true
  def handle_event("open_report", _params, socket),
    do: {:noreply, assign(socket, :reporting?, true)}

  def handle_event("cancel_report", _params, socket),
    do: {:noreply, assign(socket, :reporting?, false)}

  def handle_event("submit_report", params, %{assigns: %{current_user: user}} = socket)
      when not is_nil(user) do
    attrs = %{
      homebrew_set_id: socket.assigns.set.id,
      reason: params["reason"],
      details: blank_to_nil(params["details"])
    }

    case Homebrew.report_set(attrs, actor: user) do
      {:ok, _report} ->
        {:noreply,
         socket
         |> assign(reporting?: false, reported?: true)
         |> put_flash(:info, "Thanks — a moderator will review this set.")}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, report_error_message(error))}
    end
  end

  def handle_event("submit_report", _params, socket),
    do: {:noreply, put_flash(socket, :error, "Sign in to report a set.")}

  defp report_error_message(%Ash.Error.Invalid{errors: errors}) do
    cond do
      Enum.any?(errors, &match?(%{field: :reason}, &1)) ->
        "Pick a reason for the report."

      # The (homebrew_set_id, reporter_id) identity: one report per user.
      Enum.any?(errors, &(Exception.message(&1) =~ "already been taken")) ->
        "You've already reported this set."

      true ->
        "Could not send the report — try again."
    end
  end

  defp report_error_message(_error), do: "Could not send the report — try again."

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_value), do: nil

  defp reason_options do
    for value <- Sanctum.Homebrew.SetReportReason.values() do
      {Sanctum.Homebrew.SetReportReason.description(value), value}
    end
  end

  # One group per published descendant, in tree order, each with its cards.
  # Descendants whose parent isn't visible are hoisted to the top level
  # (Support.set_tree treats an unknown parent as a root).
  defp child_groups(set, actor, hero_colors) do
    descendants = Homebrew.list_published_descendants!(set.id, actor: actor, load: [:set_kind])

    cards_by_set =
      case descendants do
        [] ->
          %{}

        sets ->
          sets
          |> Enum.map(& &1.id)
          |> Games.list_homebrew_sets_cards!(actor: actor)
          |> Enum.group_by(& &1.homebrew_set_id)
      end

    # Children of the page's own set have a parent outside the list, so they
    # (and any orphaned descendant) come back at depth 0.
    for {child, depth} <- Support.set_tree(descendants) do
      %{
        set: child,
        depth: depth,
        cards:
          cards_by_set
          |> Map.get(child.id, [])
          |> Enum.map(&card_view(&1, &1.primary_side, hero_colors))
      }
    end
  end

  # The compact image-card map card_section renders. An unenriched card (just
  # an image, no name or type) still gets a usable map.
  defp card_view(card, nil, _hero_colors) do
    %{
      card_id: card.id,
      name: "Untitled card",
      type: nil,
      aspect_key: "encounter",
      resources: [],
      quantity: 0,
      image_url: nil,
      gradient_from: nil,
      gradient_to: nil,
      is_landscape: false
    }
  end

  defp card_view(card, side, hero_colors) do
    view = side_view(%{side | card: card}, hero_colors)
    %{view | name: view.name || "Untitled card"} |> Map.put(:quantity, 0)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash}>
      <.link
        navigate={~p"/custom"}
        class="mb-3 inline-flex items-center gap-1 font-ibm-mono text-xs uppercase tracking-[0.16em] text-base-content/50 hover:text-primary"
      >
        <.icon name="hero-arrow-left" class="size-3.5" /> Custom content
      </.link>

      <.header>
        {@set.name}
        <:actions>
          <.button
            :if={@current_user && !@reported?}
            id="report-set"
            variant="ghost"
            phx-click="open_report"
            class="px-3 py-1.5"
          >
            <.icon name="hero-flag" class="size-4" /> Report
          </.button>
          <.button
            :if={is_nil(@current_user)}
            id="report-set"
            variant="ghost"
            navigate={~p"/sign-in"}
            title="Sign in to report this set"
            class="px-3 py-1.5"
          >
            <.icon name="hero-flag" class="size-4" /> Report
          </.button>
        </:actions>
      </.header>

      <form
        :if={@reporting?}
        id="report-form"
        phx-submit="submit_report"
        class="mb-6 flex max-w-xl flex-col gap-4 border-2 border-neutral bg-base-200 p-4"
      >
        <p class="font-barlow-condensed text-sm text-base-content/70">
          Report this set to the moderators — for example if it uses art or text
          without permission. Reports are private.
        </p>
        <.input
          type="select"
          name="reason"
          id="report-reason"
          label="Reason"
          value={nil}
          prompt="Pick a reason"
          options={reason_options()}
        />
        <.input
          type="textarea"
          name="details"
          id="report-details"
          label="Details (optional)"
          value=""
          maxlength="2000"
        />
        <div class="flex items-center gap-3">
          <.button variant="primary" type="submit">Send report</.button>
          <button
            type="button"
            phx-click="cancel_report"
            class="cursor-pointer font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-base-content/60 hover:text-base-content"
          >
            Cancel
          </button>
        </div>
      </form>

      <p class="-mt-3 mb-4 font-barlow-condensed text-base-content/70">
        by
        <.link
          id="set-creator"
          navigate={~p"/custom?#{%{creator: to_string(@set.creator.username)}}"}
          class="font-bold text-primary hover:underline"
        >
          @{to_string(@set.creator.username)}
        </.link>
        <span :if={@set.visibility == :private} id="set-unpublished" class="ml-2 uppercase">
          · private — only you can see this
        </span>
        <span :if={@set.visibility == :unlisted} id="set-unlisted" class="ml-2 uppercase">
          · unlisted — only people with the link can see this
        </span>
      </p>

      <.fan_content_notice id="fan-content-notice" class="mb-6 max-w-3xl" />

      <.set_details set={@set} />

      <p
        :if={@card_tiles == [] and @child_groups == []}
        id="public-set-empty"
        class="font-barlow-condensed text-base-content/60"
      >
        No cards in this set yet.
      </p>

      <div id="public-set-contents" class="flex flex-col gap-8 pb-28">
        <div :if={@card_tiles != []} id="public-set-cards">
          <.card_section
            title={(@child_groups != [] && "In this set") || "Cards"}
            cards={@card_tiles}
            count={length(@card_tiles)}
            link?={@set.visibility == :published}
          />
        </div>

        <div
          :for={group <- @child_groups}
          id={"child-set-#{group.set.id}"}
          class={["child-set", group.depth > 0 && "border-l-2 border-neutral pl-4"]}
          style={group.depth > 1 && "margin-left: #{(group.depth - 1) * 1}rem"}
        >
          <.card_section
            title={group.set.name}
            subtitle={group.set.set_kind && group.set.set_kind.label}
            cards={group.cards}
            count={length(group.cards)}
            level={:sub}
          />
          <.link
            :if={group.set.slug}
            navigate={~p"/custom/@#{to_string(@set.creator.username)}/#{group.set.slug}"}
            class="mt-2 inline-block font-ibm-mono text-xs uppercase tracking-[0.16em] text-base-content/50 hover:text-primary"
          >
            Open set →
          </.link>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
