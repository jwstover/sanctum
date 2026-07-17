defmodule SanctumWeb.DeployNotice do
  @moduledoc """
  Warns connected users that a deploy is about to restart the app.

  CI hits `POST /internal/deploy-notice` (see `DeployNoticeController`) before
  kicking off `flyctl deploy`, giving users the image-build time (a few
  minutes) as lead time. The controller broadcasts on a PubSub topic; every
  LiveView in the router's live sessions runs the `:notify` on_mount hook,
  which subscribes and surfaces the notice as an info flash. PubSub is
  cluster-aware (DNSCluster on Fly), so users connected to any machine see it
  before their socket drops and the page live-reloads into the new version.
  """

  import Phoenix.LiveView

  @topic "sanctum:deploy_notices"
  @default_message "A new version of Sanctum is deploying — this page will refresh itself in a few minutes."

  def on_mount(:notify, _params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sanctum.PubSub, @topic)
    end

    {:cont, attach_hook(socket, :deploy_notice, :handle_info, &handle_info/2)}
  end

  @doc "Broadcasts a deploy notice to every connected LiveView across the cluster."
  def broadcast(message \\ @default_message) do
    Phoenix.PubSub.broadcast(Sanctum.PubSub, @topic, {:deploy_notice, message})
  end

  defp handle_info({:deploy_notice, message}, socket) do
    {:halt, put_flash(socket, :info, message)}
  end

  defp handle_info(_message, socket), do: {:cont, socket}
end
