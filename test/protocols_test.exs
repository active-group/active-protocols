defmodule ProtocolsTest do
  use ExUnit.Case
  import ExampleTelegrams

  alias Active.Protocols

  doctest Protocols

  defmodule Server do
    use Protocols.ReqResServer, telegrams: ExampleTelegrams.Telegram

    @impl true
    def init_session(_socket, _args) do
      # a counter as the session state
      0
    end

    @impl true
    def handle_request(request, session, _args) do
      alias ExampleTelegrams.Telegram1
      alias ExampleTelegrams.Telegram2

      case request do
        %Telegram1{} ->
          {:reply, %Telegram2{counter: session}, session + 1}
      end
    end

    @impl true
    def handle_session_error(_socket, _reason) do
      # info = :inet.peername(socket)
      # IO.puts("session failed: " <> inspect(reason))
      # called on decode errors, for logging, etc.
      :ok
    end
  end

  defmodule Client do
    use Protocols.ReqResClient, telegrams: ExampleTelegrams.Telegram
  end

  test "request-response round trip" do
    alias ExampleTelegrams.Telegram1
    alias ExampleTelegrams.Telegram2

    {:ok, pid} = Server.start_link({0, 0, 0, 0}, 0, nil)

    port = Server.get_port(pid)

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

    {:ok, pid} = Server.start_link({0, 0, 0, 0}, 0, nil)

    port = Server.get_port(pid)

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

  test "stopped server will closed connections" do
    alias ExampleTelegrams.Telegram1

    {:ok, pid} = Server.start_link({0, 0, 0, 0}, 0, nil)

    port = Server.get_port(pid)

    {:ok, conn} = Client.connect({127, 0, 0, 1}, port, 100)

    :ok = GenServer.stop(pid, :normal)

    # Note that recv fails, not the send (I think that's normal for TCP)
    assert Client.request(conn, %Telegram1{message: "Ba"}, 100) ==
             {:error, {:recv_failed, :closed}}
  end
end
