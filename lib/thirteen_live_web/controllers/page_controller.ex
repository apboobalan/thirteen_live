defmodule ThirteenLiveWeb.PageController do
  use ThirteenLiveWeb, :controller

  def howto(conn, _params) do
    conn |> render("index.html")
  end
end
