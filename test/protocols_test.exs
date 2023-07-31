defmodule ProtocolsTest do
  use ExUnit.Case

  alias Active.Protocols

  doctest Protocols

  defmodule Server do
    use Protocols.TCPServerRequestResponse, telegrams: ExampleTelegrams

    @impl true
    def init_session(_socket, _args) do
      # info = :inet.peername(socket)
      # a counter as the session state
      0
    end

    @impl true
    def handle_request(session, request) do
      alias ExampleTelegrams.Telegram1
      alias ExampleTelegrams.Telegram2

      case request do
        %Telegram1{} ->
          {:reply, %Telegram2{counter: session}, session + 1}
      end
    end

    @impl true
    def handle_error(_session, _reason) do
      # called on decode and receive errors, for logging, etc.
      :close
    end
  end

  defmodule Client do
    use Active.Protocols.TCPClientRequestResponse, telegrams: ExampleTelegrams
  end

  {:ok, _pid} = Server.start_listener(:test_server, {0, 0, 0, 0}, 0, :infinity, nil)

  test "request-response round trip" do
    alias ExampleTelegrams.Telegram1
    alias ExampleTelegrams.Telegram2

    port = Server.get_port(:test_server)

    {:ok, conn} = Client.connect({127, 0, 0, 1}, port, 100)

    assert Client.request(conn, %Telegram1{message: "Fo"}, 100) ==
             {:ok, %Telegram2{counter: 0}}

    assert Client.request(conn, %Telegram1{message: "Ba"}, 100) ==
             {:ok, %Telegram2{counter: 1}}
  end

  test "bad client stops session but not server" do
    alias ExampleTelegrams.Telegram1
    alias ExampleTelegrams.Telegram2
    alias ExampleTelegrams.InvalidTelegram

    port = Server.get_port(:test_server)

    {:ok, conn1} = Client.connect({127, 0, 0, 1}, port, 100)
    {:ok, conn2} = Client.connect({127, 0, 0, 1}, port, 100)

    # we can send an invalid telegram, but server will close connection because it cannot read it
    assert Client.request(conn1, %InvalidTelegram{}, 100) == {:error, {:recv_failed, :closed}}

    # connection is closed now, send will fail.
    assert Client.request(conn1, %Telegram1{message: "Ba"}, 100) ==
             {:error, {:send_failed, :closed}}

    # second connection still works
    assert Client.request(conn2, %Telegram1{message: "Ba"}, 100) ==
             {:ok, %Telegram2{counter: 0}}
  end

  # TODO: test making requests in chunks.

  test "stopped server will close connections" do
    alias ExampleTelegrams.Telegram1

    {:ok, pid} = Server.start_listener(:test_server2, {0, 0, 0, 0}, 0, :infinity, nil)
    port = Server.get_port(:test_server2)

    {:ok, conn} = Client.connect({127, 0, 0, 1}, port, 100)

    :ok = GenServer.stop(pid, :normal)

    assert Client.request(conn, %Telegram1{message: "Ba"}, 100) ==
             {:error, {:recv_failed, :closed}}
  end

  defmodule UDPServer do
    use Protocols.UDPServerRequestResponse, telegrams: ExampleTelegrams

    @impl true
    def init_session(_socket, _args) do
      # info = :inet.peername(socket)
      # a counter as the session state
      0
    end

    @impl true
    def handle_request(session, request) do
      alias ExampleTelegrams.Telegram1
      alias ExampleTelegrams.Telegram2

      case request do
        %Telegram1{} ->
          {:reply, %Telegram2{counter: session}, session + 1}
      end
    end

    @impl true
    def handle_error(_session, _reason) do
      # called on decode and receive errors, for logging, etc.
      :close
    end
  end

  defmodule UDPClient do
    use Active.Protocols.UDPClientRequestResponse, telegrams: ExampleTelegrams
  end

  test "udp request-response round trip" do
    alias ExampleTelegrams.Telegram1
    alias ExampleTelegrams.Telegram2

    {:ok, pid} = UDPServer.start_listener({0, 0, 0, 0}, 0, nil)

    port = UDPServer.get_port(pid)

    {:ok, conn} = UDPClient.connect({127, 0, 0, 1}, port, 100)

    assert UDPClient.request(conn, %Telegram1{message: "Fo"}, 100) ==
             {:ok, %Telegram2{counter: 0}}

    assert UDPClient.request(conn, %Telegram1{message: "Ba"}, 100) ==
             {:ok, %Telegram2{counter: 1}}
  end
end
