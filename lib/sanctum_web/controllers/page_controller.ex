defmodule SanctumWeb.PageController do
  use SanctumWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
