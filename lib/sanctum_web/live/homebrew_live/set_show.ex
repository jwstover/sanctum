defmodule SanctumWeb.HomebrewLive.SetShow do
  @moduledoc """
  A homebrew set page — the set workspace, where content is uploaded *into*
  the viewed set. One Upload button opens a chooser whose options *are* the
  file pickers (a label wrapping a hidden `live_file_input`), so choosing a
  shape opens the OS picker in the same click — no extra step, and never a
  navigation (a file dialog cannot survive one). Uploads are `auto_upload`,
  consumed as they finish in `handle_progress/3`:

    * **Card** — each image becomes a custom `Card` in this set.
    * **Alt art** — each image lands in a "to assign" strip; assigning it to an
      official card + side mints a `CardAlt` in this set
      (`Games.create_custom_alt/2`).

  The chooser asks about card *shape*, not content type: the set carries the
  kind.

  Also does front/back pairing of two single-sided cards, and moving one or
  many cards to another set of the project ("Move cards" mode,
  `Games.move_custom_cards/3`); editing a card is on its own page
  (`HomebrewLive.EditCard`).

  Sets nest to any depth within a project: the page shows ancestor
  breadcrumbs, lists its child sets, and has a parent picker
  (`Homebrew.set_set_parent/3`) that only offers sets outside this set's own
  subtree — the server rejects a cycle regardless.

  The set's own metadata — name, markdown description, banner, tags and kind —
  is edited inline ("Edit details"). The kind field is an *open* combobox: a
  text input with the project's kinds as `<datalist>` suggestions. Free text
  mints a project-scoped kind on save, blank leaves the set unclassified
  (the `:kind` argument of `HomebrewSet :update`).

  Publishing happens here, per set: the visibility panel walks the ladder
  (private → unlisted → published, and back down) through
  `Homebrew.set_set_visibility/3`, never the general update. Publishing needs
  a claimed username. Without one, the panel says why and links to `/profile`
  instead of offering Publish. The first publish also asks for the publish
  attestation, an inline checkbox recorded on the set with a timestamp.
  Unpublishing breaks public links, so it goes through a confirm dialog.
  """

  use SanctumWeb, :live_view

  import SanctumWeb.Components.CardSideTile
  import SanctumWeb.HomebrewComponents

  alias Sanctum.Games
  alias Sanctum.Homebrew
  alias Sanctum.HomebrewImages
  alias SanctumWeb.HomebrewLive.Support

  on_mount {SanctumWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(%{"project_id" => project_id, "set_id" => set_id}, _session, socket) do
    actor = socket.assigns.current_user

    with {:ok, project} <- Homebrew.get_project(project_id, actor: actor),
         {:ok, set} <- Homebrew.get_set(set_id, actor: actor, load: [:set_kind, :creator]),
         true <- set.homebrew_project_id == project.id do
      {:ok,
       socket
       |> assign(:page_title, set.name)
       |> assign(:project, project)
       |> assign(:set, set)
       |> assign(:public_path, public_path(set))
       |> assign(:hero_colors, Sanctum.Heroes.hero_color_map())
       |> assign(:uploads_configured?, HomebrewImages.configured?())
       |> assign(:pair_mode?, false)
       |> assign(:pair_selection, [])
       |> assign(:move_mode?, false)
       |> assign(:move_selection, [])
       |> assign(:chooser_open?, false)
       |> assign(:pending, [])
       |> assign(:editing_details?, false)
       |> assign(:publishing?, false)
       |> assign(:set_kinds, [])
       |> assign(:delete_impact, nil)
       |> assign_details_form()
       |> assign_structure()
       |> reset_assign()
       |> assign_cards()
       |> Support.assign_alts()
       |> allow_upload(:card_images,
         accept: ~w(.png .jpg .jpeg .webp),
         max_entries: 30,
         max_file_size: 20_000_000,
         auto_upload: true,
         progress: &handle_progress/3
       )
       |> allow_upload(:alt_images,
         accept: ~w(.png .jpg .jpeg .webp),
         max_entries: 30,
         max_file_size: 20_000_000,
         auto_upload: true,
         progress: &handle_progress/3
       )}
    else
      _not_found_or_other_project ->
        {:ok,
         socket
         |> put_flash(:error, "Set not found.")
         |> push_navigate(to: ~p"/homebrew")}
    end
  end

  # -- Upload: auto-consumed as each entry finishes ---------------------------

  # `path` below is a LiveView-owned temp-upload path, not user input (Sobelow
  # Traversal false positive, ignored project-wide).

  defp handle_progress(:card_images, entry, socket) do
    if entry.done?, do: consume_card(socket, entry), else: {:noreply, socket}
  end

  defp handle_progress(:alt_images, entry, socket) do
    if entry.done?, do: consume_alt(socket, entry), else: {:noreply, socket}
  end

  defp consume_card(socket, entry) do
    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, store_card(path, entry, socket.assigns.set, socket.assigns.current_user)}
      end)

    socket = socket |> assign(:chooser_open?, false) |> assign_cards()

    case result do
      {:ok, _card} ->
        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not add #{entry.client_name}.")}
    end
  end

  defp consume_alt(socket, entry) do
    result =
      consume_uploaded_entry(socket, entry, fn %{path: path} ->
        {:ok, HomebrewImages.store(File.read!(path), entry.client_type)}
      end)

    case result do
      {:ok, url} ->
        pending = %{
          id: System.unique_integer([:positive]),
          image_url: url,
          filename: entry.client_name
        }

        {:noreply,
         socket |> assign(:chooser_open?, false) |> update(:pending, &(&1 ++ [pending]))}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not upload #{entry.client_name}.")}
    end
  end

  defp store_card(path, entry, set, user) do
    with {:ok, body} <- File.read(path),
         {:ok, url} <- HomebrewImages.store(body, entry.client_type) do
      Games.create_custom_card(
        %{
          homebrew_set_id: set.id,
          card_sides: [%{image_url: url, filename: entry.client_name}]
        },
        actor: user
      )
    end
  end

  # -- Chooser / validation ---------------------------------------------------

  @impl true
  def handle_event("open_chooser", _params, socket) do
    {:noreply, assign(socket, :chooser_open?, true)}
  end

  def handle_event("close_chooser", _params, socket) do
    {:noreply, assign(socket, :chooser_open?, false)}
  end

  # auto_upload still fires the form's phx-change; nothing to validate.
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  # -- Set details ----------------------------------------------------------

  def handle_event("edit_details", _params, socket) do
    %{project: project, current_user: user} = socket.assigns

    {:noreply,
     socket
     |> assign(:editing_details?, true)
     |> assign(:set_kinds, Homebrew.list_project_set_kinds!(project.id, actor: user))
     |> assign_details_form()}
  end

  def handle_event("cancel_details", _params, socket) do
    {:noreply, assign(socket, :editing_details?, false)}
  end

  # Validating only builds the changeset; the kind is resolved (and possibly
  # minted) in the action's before_action, which runs on submit alone.
  def handle_event("validate_details", %{"set" => params}, socket) do
    {:noreply,
     assign(socket, :details_form, AshPhoenix.Form.validate(socket.assigns.details_form, params))}
  end

  def handle_event("save_details", %{"set" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.details_form, params: params) do
      {:ok, set} ->
        {:noreply,
         socket
         |> assign(:set, set)
         |> assign(:page_title, set.name)
         |> assign(:editing_details?, false)
         |> put_flash(:info, "Set details saved.")}

      {:error, form} ->
        {:noreply, assign(socket, :details_form, form)}
    end
  end

  # -- Visibility ladder ------------------------------------------------------

  def handle_event("start_publish", _params, socket) do
    {:noreply, assign(socket, :publishing?, true)}
  end

  def handle_event("cancel_publish", _params, socket) do
    {:noreply, assign(socket, :publishing?, false)}
  end

  def handle_event("publish", params, socket) do
    attest? = params["attest"] == "true"

    change_visibility(
      socket,
      :published,
      %{attest: attest?},
      "Published #{socket.assigns.set.name}."
    )
  end

  def handle_event("set_visibility", %{"visibility" => "unlisted"}, socket) do
    change_visibility(socket, :unlisted, %{}, "Set is now unlisted.")
  end

  def handle_event("set_visibility", %{"visibility" => "private"}, socket) do
    change_visibility(socket, :private, %{}, "Set is now private.")
  end

  # -- Delete set -------------------------------------------------------------

  # Count first, then open: the dialog states what this click would take
  # with it right now, not as of mount.
  def handle_event("prepare_delete_set", _params, socket) do
    case assign_delete_impact(socket) do
      {:ok, socket} -> {:noreply, push_open_confirm(socket, "confirm-del-set")}
      :error -> {:noreply, put_flash(socket, :error, "Could not delete the set.")}
    end
  end

  # The DB cascades the whole subtree (child sets, cards, alts, aspects).
  # Card images stay in the bucket — they are content-addressed and shared.
  def handle_event("delete_set", _params, socket) do
    %{set: set, project: project, current_user: user} = socket.assigns

    case Homebrew.destroy_set(set, actor: user) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Deleted #{set.name}.")
         |> push_navigate(to: ~p"/homebrew/#{project.id}")}

      {:error, _error} ->
        message =
          if match?(%{deck_count: n} when n > 0, socket.assigns.delete_impact),
            do: "Could not delete the set: its cards are used in decks.",
            else: "Could not delete the set."

        {:noreply, put_flash(socket, :error, message)}
    end
  end

  # -- Cards ------------------------------------------------------------------

  def handle_event("delete_card", %{"id" => id}, socket) do
    case Games.destroy_custom_card(id, actor: socket.assigns.current_user) do
      :ok -> {:noreply, assign_cards(socket)}
      _error -> {:noreply, put_flash(socket, :error, "Could not delete the card.")}
    end
  end

  # -- Alt art: pending assignment --------------------------------------------

  def handle_event("remove_pending", %{"id" => id}, socket) do
    id = String.to_integer(id)
    {:noreply, assign(socket, :pending, Enum.reject(socket.assigns.pending, &(&1.id == id)))}
  end

  def handle_event("open_assign", %{"id" => id}, socket) do
    id = String.to_integer(id)

    case Enum.find(socket.assigns.pending, &(&1.id == id)) do
      nil -> {:noreply, socket}
      pending -> {:noreply, socket |> reset_assign() |> assign(:assign_pending, pending)}
    end
  end

  def handle_event("close_assign", _params, socket) do
    {:noreply, reset_assign(socket)}
  end

  def handle_event("alt_search", %{"q" => q}, socket) do
    {:noreply,
     socket
     |> assign(:alt_search, q)
     |> assign(:alt_results, Support.search_official_sides(q, socket.assigns.current_user))}
  end

  def handle_event("pick_alt_target", %{"id" => id}, socket) do
    target = Enum.find(socket.assigns.alt_results, &(&1.id == id))
    {:noreply, assign(socket, :alt_target, target)}
  end

  def handle_event("clear_alt_target", _params, socket) do
    {:noreply, assign(socket, :alt_target, nil)}
  end

  def handle_event("create_alt", params, socket) do
    %{assign_pending: pending, alt_target: target, current_user: user, set: set} =
      socket.assigns

    with %{} <- pending,
         %{} <- target,
         {:ok, _alt} <-
           Games.create_custom_alt(
             %{
               homebrew_set_id: set.id,
               image_url: pending.image_url,
               target_card_id: target.card_id,
               side_identifier: target.side_identifier,
               artist: presence(params["artist"])
             },
             actor: user
           ) do
      {:noreply,
       socket
       |> assign(:pending, Enum.reject(socket.assigns.pending, &(&1.id == pending.id)))
       |> reset_assign()
       |> Support.assign_alts()
       |> put_flash(:info, "Alt art added for #{target.name}.")}
    else
      _missing_or_error ->
        {:noreply, put_flash(socket, :error, "Could not add the alt art.")}
    end
  end

  def handle_event("revert_alt", %{"id" => id}, socket) do
    case Games.revert_custom_alt(id, actor: socket.assigns.current_user) do
      {:ok, _new_card} ->
        {:noreply,
         socket
         |> assign_cards()
         |> Support.assign_alts()
         |> put_flash(:info, "Converted back to a card.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not revert the alt art.")}
    end
  end

  def handle_event("delete_alt", %{"id" => id}, socket) do
    {:noreply, Support.delete_alt(socket, id)}
  end

  # -- Nesting --------------------------------------------------------------

  def handle_event("set_parent", %{"parent_set_id" => parent_id}, socket) do
    %{set: set, current_user: user} = socket.assigns

    case Homebrew.set_set_parent(set, presence(parent_id), actor: user) do
      {:ok, updated} ->
        message = if updated.parent_set_id, do: "Parent set saved.", else: "Moved to top level."

        {:noreply,
         socket
         |> assign(:set, %{set | parent_set_id: updated.parent_set_id})
         |> assign_structure()
         |> put_flash(:info, message)}

      {:error, error} ->
        {:noreply,
         socket
         |> assign_structure()
         |> put_flash(:error, "Could not nest the set: #{reason(error)}")}
    end
  end

  # -- Moving cards -----------------------------------------------------------

  def handle_event("toggle_move_mode", _params, socket) do
    {:noreply,
     socket
     |> assign(:move_mode?, !socket.assigns.move_mode?)
     |> assign(:move_selection, [])
     |> assign(:pair_mode?, false)
     |> assign(:pair_selection, [])}
  end

  def handle_event("toggle_move_select", %{"id" => id}, socket) do
    selection = socket.assigns.move_selection

    selection =
      cond do
        !Enum.any?(socket.assigns.cards, &(&1.id == id)) -> selection
        id in selection -> List.delete(selection, id)
        true -> selection ++ [id]
      end

    {:noreply, assign(socket, :move_selection, selection)}
  end

  def handle_event("move_cards", %{"homebrew_set_id" => target_id}, socket) do
    %{cards: cards, move_selection: selection, current_user: user} = socket.assigns
    selected = Enum.filter(cards, &(&1.id in selection))
    target = Enum.find(socket.assigns.move_targets, &(&1.id == target_id))

    cond do
      selected == [] or is_nil(target) ->
        {:noreply, put_flash(socket, :error, "Pick cards and a set to move them to.")}

      match?(
        %Ash.BulkResult{status: :success},
        Games.move_custom_cards(selected, target.id, actor: user)
      ) ->
        {:noreply,
         socket
         |> assign(:move_mode?, false)
         |> assign(:move_selection, [])
         |> assign_cards()
         |> assign_structure()
         |> put_flash(:info, "Moved #{plural(length(selected), "card")} to #{target.name}.")}

      true ->
        {:noreply, put_flash(socket, :error, "Could not move the cards.")}
    end
  end

  # -- Pairing --------------------------------------------------------------

  def handle_event("toggle_pair_mode", _params, socket) do
    {:noreply,
     socket
     |> assign(:pair_mode?, !socket.assigns.pair_mode?)
     |> assign(:pair_selection, [])
     |> assign(:move_mode?, false)
     |> assign(:move_selection, [])}
  end

  def handle_event("toggle_pair_select", %{"id" => id}, socket) do
    selection = socket.assigns.pair_selection
    card = Enum.find(socket.assigns.cards, &(&1.id == id))

    selection =
      cond do
        is_nil(card) or card.is_multi_sided -> selection
        id in selection -> List.delete(selection, id)
        length(selection) >= 2 -> selection
        true -> selection ++ [id]
      end

    {:noreply, assign(socket, :pair_selection, selection)}
  end

  def handle_event("swap_pair_order", _params, socket) do
    {:noreply, assign(socket, :pair_selection, Enum.reverse(socket.assigns.pair_selection))}
  end

  def handle_event("pair_cards", _params, socket) do
    case socket.assigns.pair_selection do
      [front_id, back_id] ->
        case Games.pair_custom_cards(front_id, back_id, actor: socket.assigns.current_user) do
          {:ok, _paired} ->
            {:noreply,
             socket
             |> assign(:pair_mode?, false)
             |> assign(:pair_selection, [])
             |> assign_cards()
             |> put_flash(:info, "Cards paired.")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not pair the cards.")}
        end

      _incomplete ->
        {:noreply, socket}
    end
  end

  # -- Helpers ----------------------------------------------------------------

  defp change_visibility(socket, visibility, input, message) do
    %{set: set, current_user: user} = socket.assigns

    case Homebrew.set_set_visibility(set, visibility, input, actor: user) do
      {:ok, updated} ->
        # Keep the loaded :creator/:set_kind; take the fields the action writes.
        set =
          Map.merge(
            set,
            Map.take(updated, [:visibility, :slug, :attestation, :attested_at, :updated_at])
          )

        {:noreply,
         socket
         |> assign(:set, set)
         |> assign(:public_path, public_path(set))
         |> assign(:publishing?, false)
         |> put_flash(:info, message)}

      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Could not change visibility: #{reason(error)}")}
    end
  end

  # Tags are typed comma-separated; the resource takes a plain list, so the
  # split is a form concern (prepare_params), not domain logic.
  defp assign_details_form(socket) do
    set = socket.assigns.set

    form =
      AshPhoenix.Form.for_update(set, :update,
        as: "set",
        actor: socket.assigns.current_user,
        load: [:set_kind],
        params: %{
          "kind" => set.set_kind && set.set_kind.label,
          "tags" => Enum.join(set.tags || [], ", ")
        },
        prepare_params: fn params, _action ->
          case params do
            %{"tags" => tags} -> Map.put(params, "tags", split_tags(tags))
            _no_tags -> params
          end
        end
      )

    assign(socket, :details_form, to_form(form))
  end

  defp split_tags(text) when is_binary(text) do
    text
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq_by(&String.downcase/1)
  end

  defp split_tags(tags), do: tags

  # The tags input shows comma-separated text whether the form holds the
  # typed string (after a change) or the stored list (on open).
  defp tags_text(form) do
    case form[:tags].value do
      tags when is_list(tags) -> Enum.join(tags, ", ")
      text -> text
    end
  end

  defp assign_delete_impact(socket) do
    %{set: set, current_user: user} = socket.assigns

    case Homebrew.set_deletion_impact(set.id, actor: user) do
      {:ok, impact} -> {:ok, assign(socket, :delete_impact, impact)}
      {:error, _error} -> :error
    end
  end

  # The set's place in the project tree: root-first ancestor breadcrumbs, its
  # direct children (with counts), the parent picker's options (every set of
  # the project outside this set's own subtree — nesting under one of those
  # would close a cycle) and the move-cards targets (every other set).
  defp assign_structure(socket) do
    %{set: set, project: project, current_user: user} = socket.assigns

    project_sets =
      project.id
      |> Homebrew.list_project_sets!(actor: user, load: [:card_count])
      |> Enum.sort_by(& &1.inserted_at, DateTime)

    subtree_ids =
      set.id |> Homebrew.list_set_subtree!(actor: user) |> MapSet.new(& &1.id)

    ancestors = Homebrew.list_set_ancestors!(set.id, actor: user)

    socket
    |> assign(:ancestors, Support.ancestor_chain(set, ancestors))
    |> assign(:child_sets, Enum.filter(project_sets, &(&1.parent_set_id == set.id)))
    |> assign(
      :parent_options,
      for(
        {option, depth} <- Support.set_tree(project_sets),
        option.id not in subtree_ids,
        do: {String.duplicate("— ", depth) <> option.name, option.id}
      )
    )
    |> assign(:move_targets, Enum.reject(project_sets, &(&1.id == set.id)))
  end

  defp reason(%{errors: [%{message: message} | _]}) when is_binary(message), do: message
  defp reason(_error), do: "please try again."

  defp plural(1, word), do: "1 #{word}"
  defp plural(n, word), do: "#{n} #{word}s"

  defp reset_assign(socket) do
    socket
    |> assign(:assign_pending, nil)
    |> assign(:alt_search, "")
    |> assign(:alt_results, [])
    |> assign(:alt_target, nil)
  end

  defp assign_cards(socket) do
    cards =
      Games.list_homebrew_set_cards!(socket.assigns.set.id, actor: socket.assigns.current_user)

    # The pool's dossier tile, fed the primary side. side_view/2 degrades on
    # missing metadata (nil type/ownership/stats render nothing); customs have
    # no hero palette, so the color map misses and yields the fallback gradient.
    tiles =
      Enum.map(cards, fn card ->
        {card, side_view(%{card.primary_side | card: card}, socket.assigns.hero_colors)}
      end)

    socket
    |> assign(:cards, cards)
    |> assign(:card_tiles, tiles)
  end

  # The shareable /custom/@username/slug URL — only for a published set whose
  # creator has claimed a handle. Recomputed whenever the visibility changes.
  defp public_path(%{visibility: :published, slug: slug, creator: %{username: username}})
       when is_binary(slug) and not is_nil(username),
       do: ~p"/custom/@#{to_string(username)}/#{slug}"

  defp public_path(_set), do: nil

  defp presence(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp presence(_value), do: nil

  defp pair_role(id, [id | _]), do: "FRONT"
  defp pair_role(id, [_, id]), do: "BACK"
  defp pair_role(_id, _selection), do: nil

  defp card_name(cards, id) do
    case Enum.find(cards, &(&1.id == id)) do
      %{primary_side: %{name: name}} -> name
      _ -> "?"
    end
  end

  defp single_sided_count(cards), do: Enum.count(cards, &(!&1.is_multi_sided))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app current_user={@current_user} flash={@flash} active_tab={:homebrew}>
      <nav
        id="set-breadcrumbs"
        aria-label="Breadcrumb"
        class="mb-3 flex flex-wrap items-center gap-x-2 gap-y-1 font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-base-content/60"
      >
        <.link navigate={~p"/homebrew/#{@project.id}"} class="hover:text-primary">
          ← {@project.name}
        </.link>
        <%= for ancestor <- @ancestors do %>
          <span aria-hidden="true" class="text-base-content/30">/</span>
          <.link
            navigate={~p"/homebrew/#{@project.id}/sets/#{ancestor.id}"}
            class="hover:text-primary"
          >
            {ancestor.name}
          </.link>
        <% end %>
      </nav>

      <.header>
        {@set.name}
        <:actions>
          <.button :if={@public_path} id="set-public-link" variant="ghost" navigate={@public_path}>
            Public page
          </.button>
          <.button :if={!@editing_details?} phx-click="edit_details">Edit details</.button>
          <.button variant="primary" phx-click="open_chooser">Upload</.button>
          <.button
            variant="ghost"
            phx-click="prepare_delete_set"
            class="text-error hover:text-error"
          >
            Delete set
          </.button>
        </:actions>
      </.header>

      <.confirm_dialog
        id="confirm-del-set"
        message={"Delete #{@set.name} and everything in it?"}
        confirm_label="Delete set"
        phx-click="delete_set"
      >
        <ul :if={@delete_impact} class="flex flex-col gap-1 font-barlow-condensed text-sm">
          <li>
            {plural(@delete_impact.descendant_set_count, "child set")}
            <span :if={@delete_impact.descendant_set_count > 0} class="text-base-content/60">
              (at every level)
            </span>
          </li>
          <li>
            {plural(@delete_impact.card_count, "card")} and {plural(@delete_impact.alt_count, "alt")} across them
          </li>
          <li
            :if={@delete_impact.published_sets != []}
            class="border-2 border-error/70 p-2 text-error"
          >
            <span class="font-bold uppercase">Published:</span>
            {Enum.join(@delete_impact.published_sets, ", ")} — public links will stop working.
          </li>
          <li :if={@delete_impact.deck_count > 0} class="border-2 border-warning/70 p-2 text-warning">
            Cards here are used in {plural(@delete_impact.deck_count, "deck")}, which blocks
            deleting until they are removed.
          </li>
          <li class="text-base-content/60">This can't be undone.</li>
        </ul>
      </.confirm_dialog>

      <%!-- Not a header subtitle (that slot was dropped): the meta line is page
           content, and the "unofficial fan content" labeling is required on all
           homebrew surfaces (IP posture). --%>
      <p class="-mt-4 mb-5 font-barlow-condensed text-sm text-base-content/55">
        {length(@cards)} {if length(@cards) == 1, do: "card", else: "cards"}<span :if={
          @set_alts != []
        }> &middot; {length(@set_alts)} {if length(@set_alts) == 1,
          do: "alt",
          else: "alts"}</span>
        &middot; unofficial fan content
      </p>

      <.visibility_panel set={@set} publishing?={@publishing?} public_path={@public_path} />

      <.set_details_form
        :if={@editing_details?}
        form={@details_form}
        set_kinds={@set_kinds}
      />

      <.set_details :if={!@editing_details?} set={@set} />

      <.set_nesting
        set={@set}
        project={@project}
        child_sets={@child_sets}
        parent_options={@parent_options}
      />

      <div :if={@pending != []} class="mb-8 border-2 border-primary/60 bg-base-200 p-4">
        <h2 class="mb-3 font-ibm-mono text-xs uppercase tracking-[0.2em] text-primary">
          To assign ({length(@pending)}) — pick the official card each re-imagines
        </h2>
        <div class="grid grid-cols-2 gap-4 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5">
          <div :for={item <- @pending} class="flex flex-col gap-2">
            <div class="aspect-[5/7] overflow-hidden border-2 border-neutral bg-base-300">
              <img src={item.image_url} alt={item.filename} class="h-full w-full object-cover" />
            </div>
            <div class="flex items-center gap-2">
              <.button
                variant="primary"
                phx-click="open_assign"
                phx-value-id={item.id}
                class="flex-1 px-2 py-1"
              >
                Assign
              </.button>
              <button
                type="button"
                phx-click="remove_pending"
                phx-value-id={item.id}
                aria-label="Remove"
                class="cursor-pointer border-2 border-neutral px-2 py-1 font-barlow-condensed text-xs font-bold uppercase tracking-[0.06em] text-base-content/60 hover:text-base-content"
              >
                &times;
              </button>
            </div>
          </div>
        </div>
      </div>

      <div
        :if={single_sided_count(@cards) >= 2 or (@cards != [] and @move_targets != [])}
        class="mb-3 flex flex-wrap items-center gap-3"
      >
        <.button :if={!@move_mode? and single_sided_count(@cards) >= 2} phx-click="toggle_pair_mode">
          {(@pair_mode? && "Cancel pairing") || "Pair fronts & backs"}
        </.button>
        <.button
          :if={!@pair_mode? and @cards != [] and @move_targets != []}
          phx-click="toggle_move_mode"
        >
          {(@move_mode? && "Cancel moving") || "Move cards"}
        </.button>
        <span :if={@pair_mode?} class="font-barlow-condensed text-sm text-base-content/60">
          Tap two cards to pair them as one two-sided card.
        </span>
        <span :if={@move_mode?} class="font-barlow-condensed text-sm text-base-content/60">
          Tap the cards to move, then pick a set.
        </span>
      </div>

      <div
        :if={@cards == [] and @set_alts == [] and @pending == []}
        class="border-2 border-dashed border-neutral p-10 text-center"
      >
        <p class="font-barlow-condensed text-base-content/60">
          This set is empty — use <span class="font-bold text-base-content">Upload</span>
          to add cards or alt art.
        </p>
      </div>

      <div
        :if={@card_tiles != []}
        class="grid grid-cols-1 items-start gap-[18px] pb-28 sm:grid-cols-[repeat(auto-fill,minmax(452px,1fr))]"
      >
        <div :for={{card, side} <- @card_tiles} class="relative">
          <div class={[
            (pair_role(card.id, @pair_selection) || card.id in @move_selection) &&
              "outline outline-[3px] outline-primary -translate-y-0.5",
            @pair_mode? && card.is_multi_sided && "opacity-40"
          ]}>
            <.card_side_tile side={side} size="md">
              <:actions>
                <.button
                  :if={!@pair_mode? and !@move_mode?}
                  variant="ghost"
                  navigate={~p"/homebrew/#{@project.id}/cards/#{card.id}"}
                  class="px-3 py-1.5"
                >
                  Edit
                </.button>
                <.button
                  :if={!@pair_mode? and !@move_mode?}
                  variant="ghost"
                  phx-click={open_confirm("confirm-del-card-#{card.id}")}
                  class="px-3 py-1.5 text-error hover:text-error"
                >
                  Delete
                </.button>
                <.confirm_dialog
                  :if={!@pair_mode? and !@move_mode?}
                  id={"confirm-del-card-#{card.id}"}
                  message="Delete this card?"
                  confirm_label="Delete card"
                  phx-click="delete_card"
                  phx-value-id={card.id}
                />
              </:actions>
            </.card_side_tile>
          </div>

          <button
            :if={@pair_mode? && !card.is_multi_sided}
            type="button"
            phx-click="toggle_pair_select"
            phx-value-id={card.id}
            aria-label={"Select #{side.name} for pairing"}
            class="absolute inset-0 z-[3] cursor-pointer"
          ></button>

          <button
            :if={@move_mode?}
            type="button"
            phx-click="toggle_move_select"
            phx-value-id={card.id}
            aria-label={"Select #{side.name} to move"}
            aria-pressed={to_string(card.id in @move_selection)}
            class="absolute inset-0 z-[3] cursor-pointer"
          ></button>

          <span
            :if={card.id in @move_selection}
            class="absolute left-1 top-1 z-[4] border-2 border-neutral bg-primary px-1.5 font-barlow-condensed text-xs font-bold text-primary-content"
          >
            MOVE
          </span>

          <span
            :if={role = pair_role(card.id, @pair_selection)}
            class="absolute left-1 top-1 z-[4] border-2 border-neutral bg-primary px-1.5 font-barlow-condensed text-xs font-bold text-primary-content"
          >
            {role}
          </span>
          <span
            :if={@pair_mode? && card.is_multi_sided}
            class="absolute left-1 top-1 z-[4] border-2 border-neutral bg-base-300 px-1.5 font-barlow-condensed text-xs font-bold text-base-content/70"
          >
            2-SIDED
          </span>
        </div>
      </div>

      <.alt_art_section
        alt_tiles={@alt_tiles}
        count={length(@set_alts)}
        revert?={true}
        class="mt-8"
      />

      <.pair_strip
        :if={@pair_mode? && length(@pair_selection) == 2}
        pair_selection={@pair_selection}
        cards={@cards}
      />

      <.move_strip
        :if={@move_mode? && @move_selection != []}
        count={length(@move_selection)}
        move_targets={@move_targets}
      />

      <.upload_chooser
        open?={@chooser_open?}
        uploads_configured?={@uploads_configured?}
        card_upload={@uploads.card_images}
        alt_upload={@uploads.alt_images}
      />

      <.assign_sheet
        assign_pending={@assign_pending}
        alt_search={@alt_search}
        alt_results={@alt_results}
        alt_target={@alt_target}
      />
    </Layouts.app>
    """
  end

  # The Upload shape chooser (the app's sheet shell recipe): each option is a
  # <label> wrapping a hidden auto-upload file input, so choosing a shape opens
  # the OS picker in the same click. Never make an option navigate first — a
  # file dialog cannot survive a navigation. The inputs stay in the DOM even when the
  # sheet is hidden (transform + inert), so in-flight uploads survive closing.
  attr :open?, :boolean, required: true
  attr :uploads_configured?, :boolean, required: true
  attr :card_upload, :any, required: true
  attr :alt_upload, :any, required: true

  defp upload_chooser(assigns) do
    ~H"""
    <div
      :if={@open?}
      phx-click="close_chooser"
      phx-window-keydown="close_chooser"
      phx-key="escape"
      aria-hidden="true"
      class="fixed inset-0 z-40 bg-black/60"
    >
    </div>
    <section
      id="upload-chooser-sheet"
      phx-hook="PaneDrag"
      data-dismiss-event="close_chooser"
      role="dialog"
      aria-modal="true"
      aria-label="Upload"
      inert={!@open?}
      class={[
        "fixed inset-x-0 bottom-0 z-50 flex max-h-[85dvh] flex-col border-t-2 border-neutral bg-base-100",
        "transition-transform duration-200",
        "sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-[12dvh] sm:max-h-[80dvh] sm:w-[520px]",
        "sm:-translate-x-1/2 sm:border-2 sm:shadow-comic sm:transition-none",
        (@open? && "translate-y-0") || "translate-y-full sm:hidden"
      ]}
    >
      <button
        type="button"
        data-drag-handle
        data-haptic
        class="flex w-full flex-none cursor-grab touch-none items-center justify-center gap-2 py-3 text-base-content/50 sm:hidden"
        title="Close"
      >
        <span class="h-1 w-10 rounded-full bg-base-content/25"></span>
        <.icon name="hero-chevron-down" class="size-4" />
      </button>

      <header class="hidden flex-none items-center justify-between border-b-2 border-line px-5 py-3 sm:flex">
        <h2 class="font-bangers text-[22px] tracking-[0.02em] text-primary">What are you adding?</h2>
        <button
          type="button"
          phx-click="close_chooser"
          aria-label="Close"
          class="grid size-8 cursor-pointer place-items-center text-base-content/50 hover:text-white"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </header>

      <div class="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto px-4 py-4 sm:px-5">
        <.upload_unconfigured_notice :if={!@uploads_configured?} />

        <form :if={@uploads_configured?} id="homebrew-uploads" phx-change="validate">
          <div class="flex flex-col gap-3">
            <label class="group flex cursor-pointer items-center gap-4 border-2 border-neutral bg-base-200 p-4 transition-colors hover:border-primary">
              <.live_file_input upload={@card_upload} class="sr-only" />
              <.icon name="hero-rectangle-stack" class="size-7 shrink-0 text-primary" />
              <span class="min-w-0">
                <span class="block font-barlow-condensed text-base font-bold uppercase tracking-[0.05em]">
                  Card
                </span>
                <span class="block font-barlow-condensed text-sm text-base-content/60">
                  Each image becomes a card in this set.
                </span>
              </span>
            </label>

            <label class="group flex cursor-pointer items-center gap-4 border-2 border-neutral bg-base-200 p-4 transition-colors hover:border-primary">
              <.live_file_input upload={@alt_upload} class="sr-only" />
              <.icon name="hero-photo" class="size-7 shrink-0 text-primary" />
              <span class="min-w-0">
                <span class="block font-barlow-condensed text-base font-bold uppercase tracking-[0.05em]">
                  Alt art
                </span>
                <span class="block font-barlow-condensed text-sm text-base-content/60">
                  New art for official cards — assign each image to a card.
                </span>
              </span>
            </label>
          </div>
        </form>
      </div>
    </section>
    """
  end

  # The assignment bottom sheet: search an official card, pick a printed side,
  # credit the artist, create the alt. Openness keys off @assign_pending.
  attr :assign_pending, :any, required: true
  attr :alt_search, :string, required: true
  attr :alt_results, :list, required: true
  attr :alt_target, :any, required: true

  defp assign_sheet(assigns) do
    ~H"""
    <div
      :if={@assign_pending}
      phx-click="close_assign"
      phx-window-keydown="close_assign"
      phx-key="escape"
      aria-hidden="true"
      class="fixed inset-0 z-40 bg-black/60"
    >
    </div>
    <section
      id="assign-alt-sheet"
      phx-hook="PaneDrag"
      data-dismiss-event="close_assign"
      role="dialog"
      aria-modal="true"
      aria-label="Assign alt art"
      inert={is_nil(@assign_pending)}
      class={[
        "fixed inset-x-0 bottom-0 z-50 flex max-h-[85dvh] flex-col border-t-2 border-neutral bg-base-100",
        "transition-transform duration-200",
        "sm:inset-x-auto sm:bottom-auto sm:left-1/2 sm:top-[7dvh] sm:max-h-[86dvh] sm:w-[560px]",
        "sm:-translate-x-1/2 sm:border-2 sm:shadow-comic sm:transition-none",
        (@assign_pending && "translate-y-0") || "translate-y-full sm:hidden"
      ]}
    >
      <button
        type="button"
        data-drag-handle
        data-haptic
        class="flex w-full flex-none cursor-grab touch-none items-center justify-center gap-2 py-3 text-base-content/50 sm:hidden"
        title="Close"
      >
        <span class="h-1 w-10 rounded-full bg-base-content/25"></span>
        <.icon name="hero-chevron-down" class="size-4" />
      </button>

      <header class="hidden flex-none items-center justify-between border-b-2 border-line px-5 py-3 sm:flex">
        <h2 class="font-bangers text-[22px] tracking-[0.02em] text-primary">Assign Alt Art</h2>
        <button
          type="button"
          phx-click="close_assign"
          aria-label="Close"
          class="grid size-8 cursor-pointer place-items-center text-base-content/50 hover:text-white"
        >
          <.icon name="hero-x-mark" class="size-5" />
        </button>
      </header>

      <div :if={@assign_pending} class="min-h-0 flex-1 overflow-y-auto px-4 py-4 sm:px-5">
        <div class="mb-4 flex items-center gap-3">
          <div class="aspect-[5/7] w-16 shrink-0 overflow-hidden border-2 border-neutral">
            <img src={@assign_pending.image_url} alt="alt art" class="h-full w-full object-cover" />
          </div>
          <p class="font-barlow-condensed text-[14px] text-base-content/70">
            Pick the official card this art re-imagines. It appears as fan art on that
            card's page; your image is never a new card.
          </p>
        </div>

        <div :if={is_nil(@alt_target)} id="alt-search-nav" phx-hook="AltSearchNav">
          <%!-- The hook (mounted when this appears) focuses the input and drives
               ArrowUp/Down + Enter over the [data-alt-result] buttons below. --%>
          <form id="assign-alt-search" phx-change="alt_search" onsubmit="return false">
            <.input
              type="text"
              name="q"
              value={@alt_search}
              label="Official card"
              placeholder="Search by name…"
              autocomplete="off"
              phx-debounce="250"
            />
          </form>

          <div class="mt-3 flex flex-col">
            <button
              :for={side <- @alt_results}
              type="button"
              data-alt-result
              phx-click="pick_alt_target"
              phx-value-id={side.id}
              class="flex cursor-pointer items-center gap-3 border-b border-neutral/40 py-2 text-left hover:bg-base-200"
            >
              <div class="aspect-[5/7] w-10 shrink-0 overflow-hidden border border-neutral">
                <img
                  :if={side.image_url}
                  src={side.image_url}
                  alt={side.name}
                  loading="lazy"
                  class="h-full w-full object-cover"
                />
              </div>
              <span class="min-w-0 flex-1 truncate font-barlow-condensed text-[14px] font-bold uppercase tracking-[0.04em]">
                {side.name}
              </span>
              <span class="shrink-0 font-ibm-mono text-[11px] text-base-content/50">
                {side.code}<span :if={side.card && side.card.pack}> · {side.card.pack}</span>
              </span>
            </button>
          </div>
        </div>

        <div :if={@alt_target} class="flex flex-col gap-4">
          <div class="flex items-center justify-between gap-3 border-2 border-neutral bg-base-200 px-3 py-2">
            <span class="font-barlow-condensed text-[14px] font-bold uppercase tracking-[0.04em]">
              Alt art for {@alt_target.name}
              <span class="font-ibm-mono text-[11px] font-normal text-base-content/50">
                ({@alt_target.code})
              </span>
            </span>
            <button
              type="button"
              phx-click="clear_alt_target"
              class="shrink-0 cursor-pointer font-barlow-condensed text-[13px] font-bold uppercase tracking-[0.08em] text-base-content/60 hover:text-base-content"
            >
              Change
            </button>
          </div>

          <form
            id="assign-alt-form"
            phx-hook="AutoFocus"
            phx-submit="create_alt"
            class="flex flex-col gap-4"
          >
            <.input
              type="text"
              name="artist"
              value=""
              label="Artist credit (optional)"
              autocomplete="off"
            />
            <.button variant="primary" type="submit" class="self-end">
              Add alt art
            </.button>
          </form>
        </div>
      </div>
    </section>
    """
  end

  # The publish ladder. Publishing is inline (a checkbox can't ride the
  # confirm dialog's button), and the attestation is asked only the first time.
  # Without a creator username, the Publish button is replaced by the reason
  # and a link to claim one. Unpublishing breaks public links, so it confirms.
  attr :set, :any, required: true
  attr :publishing?, :boolean, required: true
  attr :public_path, :string, default: nil

  defp visibility_panel(assigns) do
    assigns = assign(assigns, :username?, not is_nil(assigns.set.creator.username))

    ~H"""
    <.panel id="set-visibility" class="mb-8 p-4">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div class="flex items-center gap-2 font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em]">
          <span
            :for={rung <- [:private, :unlisted, :published]}
            id={"visibility-rung-#{rung}"}
            aria-current={rung == @set.visibility && "true"}
            class={[
              "border-2 px-2 py-0.5",
              (rung == @set.visibility && "border-primary bg-primary text-primary-content") ||
                "border-neutral text-base-content/50"
            ]}
          >
            {rung}
          </span>
        </div>

        <div :if={!@publishing?} class="flex flex-wrap items-center gap-2">
          <.button
            :if={@set.visibility == :private}
            id="make-unlisted"
            variant="ghost"
            phx-click="set_visibility"
            phx-value-visibility="unlisted"
          >
            Make unlisted
          </.button>
          <.button
            :if={@set.visibility == :unlisted}
            id="make-private"
            variant="ghost"
            phx-click="set_visibility"
            phx-value-visibility="private"
          >
            Make private
          </.button>
          <.button
            :if={@set.visibility != :published and @username?}
            id="start-publish"
            variant="primary"
            phx-click="start_publish"
          >
            Publish
          </.button>
          <.button
            :if={@set.visibility == :published}
            id="unpublish"
            variant="ghost"
            phx-click={open_confirm("confirm-unpublish")}
            class="text-error hover:text-error"
          >
            Unpublish
          </.button>
        </div>
      </div>

      <p class="mt-2 font-barlow-condensed text-sm text-base-content/60">
        <%= case @set.visibility do %>
          <% :private -> %>
            Only you can see this set.
          <% :unlisted -> %>
            Hidden from browsing — only you can see it until share links arrive.
          <% :published -> %>
            Anyone can see this set and its cards<span :if={@public_path}> at
              <.link navigate={@public_path} class="underline hover:text-primary">{@public_path}</.link></span>.
        <% end %>
      </p>

      <p
        :if={@set.visibility != :published and !@username?}
        id="publish-needs-username"
        class="mt-3 border-2 border-warning/70 p-3 font-barlow-condensed text-sm text-warning"
      >
        To publish, claim a username first. Published sets are credited to your
        username, and it forms their public link.
        <.link navigate={~p"/profile"} class="font-bold underline">Claim a username</.link>
      </p>

      <form
        :if={@publishing?}
        id="publish-form"
        phx-submit="publish"
        class="mt-4 flex flex-col gap-4 border-t-2 border-neutral pt-4"
      >
        <.input
          :if={is_nil(@set.attested_at)}
          type="checkbox"
          name="attest"
          id="publish-attest"
          value={false}
          label="I'm allowed to distribute this set publicly, under my username: it is my own work, or shared with its creator's permission."
        />
        <p :if={@set.attested_at} class="font-barlow-condensed text-sm text-base-content/60">
          You attested to publishing this set on {Calendar.strftime(@set.attested_at, "%b %-d, %Y")}.
        </p>
        <div class="flex items-center gap-3">
          <.button variant="primary" type="submit">Publish set</.button>
          <button
            type="button"
            phx-click="cancel_publish"
            class="cursor-pointer font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-base-content/60 hover:text-base-content"
          >
            Cancel
          </button>
        </div>
      </form>

      <.confirm_dialog
        id="confirm-unpublish"
        message={"Unpublish #{@set.name}?"}
        confirm_label="Unpublish"
        phx-click="set_visibility"
        phx-value-visibility="private"
      >
        <p class="font-barlow-condensed text-sm text-base-content/70">
          It goes back to private: its public link stops working and its cards
          disappear for everyone else.
        </p>
      </.confirm_dialog>
    </.panel>
    """
  end

  # Inline (never modal) metadata editor. The kind input is an open
  # combobox: <datalist> suggestions, free text allowed, blank = unclassified.
  attr :form, :any, required: true
  attr :set_kinds, :list, required: true

  defp set_details_form(assigns) do
    ~H"""
    <.panel class="mb-8 p-5">
      <.form
        for={@form}
        id="set-details-form"
        phx-change="validate_details"
        phx-submit="save_details"
      >
        <div class="flex flex-col gap-4">
          <.input field={@form[:name]} type="text" label="Set name" autocomplete="off" />

          <div>
            <.input
              field={@form[:kind]}
              type="text"
              label="Kind (optional)"
              list="set-kind-options"
              placeholder="Hero, Scenario… or type your own"
              autocomplete="off"
            />
            <datalist id="set-kind-options">
              <option :for={kind <- @set_kinds} value={kind.label} />
            </datalist>
            <p class="mt-1 font-barlow-condensed text-xs text-base-content/50">
              Pick a suggestion or type a new kind; leave blank for unclassified.
            </p>
          </div>

          <.input
            field={@form[:tags]}
            value={tags_text(@form)}
            type="text"
            label="Tags (comma-separated)"
            autocomplete="off"
          />

          <.input
            field={@form[:banner_url]}
            type="url"
            label="Banner image URL"
            placeholder="https://…"
            autocomplete="off"
          />

          <.input
            field={@form[:description]}
            type="textarea"
            label="Description (markdown)"
            rows="6"
          />

          <div class="flex items-center gap-3">
            <.button variant="primary" type="submit">Save details</.button>
            <button
              type="button"
              phx-click="cancel_details"
              class="cursor-pointer font-barlow-condensed text-sm font-bold uppercase tracking-[0.08em] text-base-content/60 hover:text-base-content"
            >
              Cancel
            </button>
          </div>
        </div>
      </.form>
    </.panel>
    """
  end

  # Where the set sits in its project's tree: its child sets (each a link with
  # its card count) and the parent picker. The picker only lists sets outside
  # this set's subtree; "Top level" clears the link.
  attr :set, :any, required: true
  attr :project, :any, required: true
  attr :child_sets, :list, required: true
  attr :parent_options, :list, required: true

  defp set_nesting(assigns) do
    ~H"""
    <div class="mb-8 flex flex-col gap-4">
      <section :if={@child_sets != []} id="child-sets">
        <h2 class="mb-2 font-ibm-mono text-xs uppercase tracking-[0.2em] text-base-content/60">
          Child sets ({length(@child_sets)})
        </h2>
        <div class="flex flex-wrap gap-3">
          <.link
            :for={child <- @child_sets}
            id={"child-set-#{child.id}"}
            navigate={~p"/homebrew/#{@project.id}/sets/#{child.id}"}
          >
            <.panel class="px-4 py-2 transition-transform hover:-translate-y-0.5">
              <div class="font-anton text-sm uppercase tracking-[0.05em]">{child.name}</div>
              <div class="font-barlow-condensed text-xs text-base-content/60">
                {plural(child.card_count, "card")}
              </div>
            </.panel>
          </.link>
        </div>
      </section>

      <form
        id="set-parent-form"
        phx-submit="set_parent"
        class="flex flex-wrap items-end gap-2 font-barlow-condensed text-sm"
      >
        <label class="flex flex-col gap-1">
          <span class="font-bold uppercase tracking-[0.08em] text-base-content/60">
            Parent set
          </span>
          <select
            name="parent_set_id"
            class="select select-sm min-w-56 border-2 border-neutral bg-base-200"
          >
            <option value="" selected={is_nil(@set.parent_set_id)}>Top level (no parent)</option>
            <option
              :for={{label, id} <- @parent_options}
              value={id}
              selected={id == @set.parent_set_id}
            >
              {label}
            </option>
          </select>
        </label>
        <.button type="submit" class="px-3 py-1.5">Save parent</.button>
      </form>
    </div>
    """
  end

  # Bottom action strip once cards are selected for moving: the target is
  # any other set of this project (cross-project moves are not offered).
  attr :count, :integer, required: true
  attr :move_targets, :list, required: true

  defp move_strip(assigns) do
    ~H"""
    <div class="fixed inset-x-0 bottom-0 z-20 border-t-2 border-neutral bg-base-100/95 px-4 py-3 backdrop-blur sm:sticky sm:bottom-4 sm:border-2 sm:bg-base-200 sm:px-5 sm:py-4 sm:shadow-comic">
      <form
        id="move-cards-form"
        phx-submit="move_cards"
        class="mx-auto flex max-w-3xl flex-col gap-3 sm:flex-row sm:items-center sm:justify-between"
      >
        <span class="font-barlow-condensed text-sm font-bold uppercase tracking-[0.05em]">
          Move {plural(@count, "card")} to
        </span>
        <div class="flex items-center gap-2">
          <select
            name="homebrew_set_id"
            aria-label="Target set"
            class="select select-sm min-w-48 border-2 border-neutral bg-base-100"
          >
            <option :for={target <- @move_targets} value={target.id}>{target.name}</option>
          </select>
          <.button variant="primary" type="submit">Move</.button>
        </div>
      </form>
    </div>
    """
  end

  # Fixed bottom action strip once two cards are selected for pairing —
  # deck_live/new.ex's confirm-strip recipe (never a modal).
  defp pair_strip(assigns) do
    ~H"""
    <div class="fixed inset-x-0 bottom-0 z-20 border-t-2 border-neutral bg-base-100/95 px-4 py-3 backdrop-blur sm:sticky sm:bottom-4 sm:border-2 sm:bg-base-200 sm:px-5 sm:py-4 sm:shadow-comic">
      <div class="mx-auto flex max-w-3xl flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <span class="font-barlow-condensed text-sm font-bold uppercase tracking-[0.05em]">
          Front: {card_name(@cards, Enum.at(@pair_selection, 0))}
          <span class="text-base-content/50">→</span>
          Back: {card_name(@cards, Enum.at(@pair_selection, 1))}
        </span>
        <div class="flex items-center gap-2">
          <.button type="button" phx-click="swap_pair_order">Swap</.button>
          <.button variant="primary" type="button" phx-click="pair_cards">
            Pair as one card
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
