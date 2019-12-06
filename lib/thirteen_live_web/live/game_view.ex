defmodule ThirteenLiveWeb.GameView do
  use Phoenix.LiveView
  alias ThirteenLiveWeb.Router.Helpers, as: Routes

  @flash_timeout 2000

  def handle_event(
        "validate",
        %{
          "game" => %{"name" => game_name, "player_name" => player_name, "password" => password}
        },
        socket
      ) do
    socket =
      socket
      |> assign(game_input: %{name: game_name, player_name: player_name, password: password})
      |> valid_input?(game_name, "Game Name")
      |> valid_input?(player_name, "Player Name")
      |> valid_input?(password, "Password")

    game_name = socket.assigns.game_input.name

    {:noreply,
     live_redirect(
       socket,
       to: Routes.live_path(socket, ThirteenLiveWeb.GameView, game_name)
     )}
  end

  def handle_event("join_game", %{"game" => %{"name" => ""}}, socket) do
    show_error("Fill Game Name.")
    {:noreply, socket}
  end

  def handle_event("join_game", %{"game" => %{"player_name" => ""}}, socket) do
    show_error("Fill Player Name.")
    {:noreply, socket}
  end

  def handle_event(
        "join_game",
        %{
          "game" => %{"name" => game_name, "player_name" => player_name, "password" => password}
        },
        socket
      ) do
    game_name |> Thirteen.new()

    unless game_name |> game_lobby_created? do
      game_name |> create_game_lobby
    end

    socket = socket |> assign(game_name: game_name)

    case game_name |> Thirteen.join(player_name) do
      {:ok, _} ->
        socket =
          socket |> merge_player_and_socket(%{"name" => player_name, "password" => password})

        {:noreply, socket}

      {:error, :PLAYER_NAME_ALREADY_EXISTS} ->
        socket =
          socket |> merge_player_and_socket(%{"name" => player_name, "password" => password})

        {:noreply, socket}

      {:error, :NO_MORE_PLAYERS} ->
        show_error("Maximum players joined. Join another game.")
        {:noreply, socket}

      {:error, :GAME_IN_PROGRESS} ->
        show_error("Game in progress. wait for the completion.")
        {:noreply, socket}
    end
  end

  def handle_event("start_game", _value, socket) do
    case socket.assigns.game_name |> Thirteen.start() do
      {:ok, _} ->
        message = "Game Started."
        show_info(message)
        broadcast("info_broadcast", %{message: message})
        show_game()
        broadcast("show_game")
        {:noreply, socket |> assign(start_view: "hidden", bet_view: "block")}

      {:error, :LESS_PLAYERS} ->
        show_error("Add more players to start game.")
        {:noreply, socket}
    end
  end

  def handle_event("place_bet", %{"value" => bet}, socket) do
    game_name = socket.assigns.game_name
    player_name = socket.assigns.player_name

    case game_name |> Thirteen.play(player_name, bet) do
      {:ok, _} ->
        show_info("You bet #{bet}.")
        broadcast("info_broadcast", %{message: "#{player_name} bet #{bet}."})
        show_game()
        broadcast("show_game")

      {:error, :ANOTHER_PLAYER_TURN} ->
        show_error("Another player turn.")
    end

    {:noreply, socket}
  end

  def handle_event("play_card", %{"value" => card}, socket) do
    in_bet_view? = socket.assigns.bet_view == "block"

    if !in_bet_view? do
      game_name = socket.assigns.game_name
      player_name = socket.assigns.player_name

      case game_name |> Thirteen.play(player_name, card) do
        {:ok, _} ->
          broadcast("play_card", %{player_name: player_name, card: card})
          show_game()
          broadcast("show_game")

        {:error, :ANOTHER_PLAYER_TURN} ->
          show_error("Another player turn.")

        {:error, :BETTER_CARD_AVAILABLE} ->
          show_error("Better card available.")
      end

      {:noreply, socket}
    else
      show_error("Please place bet first.")
      {:noreply, socket}
    end
  end

  def handle_event("restart_game", _value, socket) do
    broadcast("restart_game")
    restart_game()
    {:noreply, socket}
  end

  def handle_event("copy_url", _value, socket) do
    show_info("copied.")
    {:noreply, socket}
  end

  defp show_info(info), do: self() |> send({:info, info})
  defp show_error(error), do: self() |> send({:error, error})
  defp show_played_card(played), do: self() |> send({:card_played, played})
  defp show_game(), do: self() |> send(:show_game)
  defp restart_game(), do: self() |> send(:restart_game)

  defp show_bet(socket, game) do
    socket |> assign(start_view: "hidden", bet_view: "block", bet_count: game["cards"])
  end

  defp show_hand(socket, game) do
    game_name = socket.assigns.game_name
    player_name = socket.assigns.player_name
    {:ok, hand} = game_name |> Thirteen.cards(player_name)

    socket
    |> assign(
      bet_view: "hidden",
      hand_view: "block",
      table_view: "block",
      result_view: "block",
      table: game["on_table"] |> Enum.map(&expand_card/1),
      hand: hand |> Enum.map(&expand_card/1),
      result: game["result"] |> Enum.map(&expand_player/1)
    )
  end

  defp show_playing_now(socket, game) do
    socket
    |> assign(
      playing_now: %{visibility: "block", player_name: game["playing_now"], round: game["cards"]}
    )
  end

  defp hide_playing_now(socket),
    do: socket |> assign(playing_now: %{visibility: "hidden", player_name: "", round: ""})

  defp show_finished(socket, game) do
    self() |> Process.send_after(:restart_game, 5000)

    socket
    |> assign(
      hand_view: "hidden",
      table_view: "hidden",
      result: game["points_order"] |> Enum.map(&"#{&1.player.name} &spades; #{&1.points}")
    )
  end

  def handle_info(:show_game, socket) do
    {:ok, game} = socket.assigns.game_name |> Thirteen.game_state()

    socket =
      case game["state"] do
        "bet" ->
          socket |> show_hand(game) |> show_bet(game) |> show_playing_now(game)

        "throw_card" ->
          socket |> show_hand(game) |> show_playing_now(game)

        "finished" ->
          socket |> show_finished(game) |> hide_playing_now()
      end

    {:noreply, socket}
  end

  def handle_info(:restart_game, socket) do
    game_name = socket.assigns.game_name
    url = socket.assigns.url
    game_input = socket.assigns.game_input
    game_name |> unsubscribe
    game_name |> stop_game
    game_name |> clear_lobby

    socket =
      socket
      |> assign(initial_state())
      |> assign(url: url)
      |> assign(game_name: game_name)
      |> assign(game_input: game_input)

    {:noreply, socket |> assign(initial_state())}
  end

  def handle_info({:info, info}, socket) do
    self() |> Process.send_after(:hide_info, @flash_timeout)
    {:noreply, socket |> assign(info: %{visibility: "block", message: info})}
  end

  def handle_info({:error, error}, socket) do
    self() |> Process.send_after(:hide_error, @flash_timeout)
    {:noreply, socket |> assign(error: %{visibility: "block", message: error})}
  end

  def handle_info({:card_played, played}, socket) do
    self() |> Process.send_after(:hide_played_card, @flash_timeout)

    {:noreply,
     socket
     |> assign(
       played_card: %{
         visibility: "block",
         player: played.player_name,
         card: played.card |> encode_card
       }
     )}
  end

  def handle_info(:hide_played_card, socket),
    do: {:noreply, socket |> assign(played_card: %{visibility: "hidden", player: "", card: ""})}

  def handle_info(:hide_info, socket),
    do: {:noreply, socket |> assign(info: %{visibility: "hidden", message: ""})}

  def handle_info(:hide_error, socket),
    do: {:noreply, socket |> assign(error: %{visibility: "hidden", message: ""})}

  def handle_info({:broadcast, topic, payload}, socket) do
    ThirteenLiveWeb.Endpoint.broadcast_from(self(), socket.assigns.game_name, topic, payload)
    {:noreply, socket}
  end

  def handle_info(%{payload: payload, event: "info_broadcast"}, socket) do
    show_info(payload.message)
    {:noreply, socket}
  end

  def handle_info(%{payload: played, event: "play_card"}, socket) do
    show_played_card(played)
    {:noreply, socket}
  end

  def handle_info(%{event: "restart_game"}, socket) do
    restart_game()
    {:noreply, socket}
  end

  def handle_info(%{event: "show_game"}, socket) do
    show_game()
    {:noreply, socket}
  end

  def render(assigns) do
    ThirteenLiveWeb.PageView.render("game.html", assigns)
  end

  defp subscribe(game), do: ThirteenLiveWeb.Endpoint.subscribe(game)
  defp unsubscribe(game), do: ThirteenLiveWeb.Endpoint.unsubscribe(game)
  defp broadcast(topic, payload \\ %{}), do: self() |> send({:broadcast, topic, payload})

  defp valid_input?(socket, field, field_label) do
    socket =
      if !(field |> valid_input_value?) do
        show_error(
          "No special characters allowed in #{field_label} other than Alphabets, Numbers. Length not more than 10."
        )

        socket |> reset_input_field(field_label)
      else
        socket
      end

    socket
  end

  defp reset_input_field(socket, "Game Name") do
    game_input = socket.assigns.game_input
    socket |> assign(game_input: %{game_input | name: ""})
  end

  defp reset_input_field(socket, "Player Name") do
    game_input = socket.assigns.game_input
    socket |> assign(game_input: %{game_input | player_name: ""})
  end

  defp reset_input_field(socket, "Password") do
    game_input = socket.assigns.game_input
    socket |> assign(game_input: %{game_input | password: ""})
  end

  defp valid_input_value?(input),
    do: (input == "" or Regex.match?(~r/^[a-z0-9]+$/i, input)) and input |> String.length() < 11

  @face_shape %{
    "A" => "&spades;",
    "C" => "&clubs;",
    "D" => "&diams;",
    "H" => "&hearts;",
    "" => ""
  }
  @face_color %{
    "A" => "black",
    "C" => "black",
    "D" => "yellow-500",
    "H" => "yellow-500",
    "" => "black"
  }
  defp encode_card(card) do
    value = card |> String.slice(0..-2)
    face = card |> String.last()
    "<text class=\"text-#{@face_color[face]}\">#{value}#{@face_shape[face]}</text>"
  end

  defp expand_card(card) do
    value = card |> String.slice(0..-2)
    face = card |> String.last()

    %{
      value: value,
      name: card,
      color: @face_color[face],
      shape: @face_shape[face]
    }
  end

  defp expand_player(result) do
    "#{result.player.name} &spades; #{result.bet} &spades; #{result.current} &spades; #{
      result.points
    }"
  end

  def handle_params(%{"game_name" => game_name}, url, socket) do
    player_name = socket.assigns.game_input.player_name
    password = socket.assigns.game_input.password

    socket =
      socket
      |> assign(url: url)
      |> assign(game_name: game_name)
      |> assign(game_input: %{name: game_name, player_name: player_name, password: password})

    {:noreply, socket}
  end

  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  def mount(_session, socket) do
    {:ok, socket |> assign(initial_state())}
  end

  def initial_state do
    %{
      url: "",
      init_view: "block",
      start_view: "hidden",
      bet_view: "hidden",
      hand_view: "hidden",
      table_view: "hidden",
      result_view: "hidden",
      bet_count: 0,
      hand: [],
      table: [],
      result: [],
      playing_now: %{visibility: "hidden", player_name: "", round: ""},
      played_card: %{visibility: "hidden", player: "", card: ""},
      game_input: %{name: "", player_name: "", password: ""},
      info: %{visibility: "hidden", message: ""},
      error: %{visibility: "hidden", message: ""}
    }
  end

  defp stop_game(game_name) do
    case game_name |> Thirteen.alive?() do
      true -> game_name |> Thirteen.stop()
      false -> :ok
    end
  end

  defp game_lobby_created?(name) do
    case Process.whereis(name |> String.to_atom()) do
      nil -> false
      _ -> true
    end
  end

  defp create_game_lobby(name) do
    Agent.start_link(fn -> [] end, name: name |> String.to_atom())
  end

  defp clear_lobby(name) do
    agent_name = name |> String.to_atom()

    case Process.whereis(agent_name) do
      nil -> :ok
      _ -> agent_name |> Agent.stop()
    end
  end

  defp add_player_to_lobby(lobby, player) do
    lobby |> String.to_atom() |> Agent.update(&[player | &1])
  end

  defp get_players(lobby), do: Agent.get(lobby |> String.to_atom(), & &1)

  defp merge_player_and_socket(socket, %{"name" => name, "password" => password} = player) do
    game_name = socket.assigns.game_name
    players = game_name |> get_players

    case players |> Enum.find(&(&1["name"] == name)) do
      nil ->
        socket = socket |> assign(:player_name, name)
        game_name |> add_player_to_lobby(player)
        subscribe(game_name)
        broadcast("info_broadcast", %{message: "#{name} joined."})
        socket |> assign(init_view: "hidden", start_view: "block")

      player ->
        case player["password"] == password do
          true ->
            socket = socket |> assign(:player_name, name)
            show_info("#{name} already playing, so merged.")
            subscribe(game_name)
            socket |> assign(init_view: "hidden", start_view: "block")

          false ->
            show_error(
              "A player named #{name} already playing. If you are the same player, enter same password."
            )

            socket
        end
    end
  end
end
