defmodule ProtocolsTest do
  use ExUnit.Case
  import ExampleTelegrams

  doctest Protocols

  defmodule TelegramTransport do
    use Protocols.TCPTransport, telegrams: ExampleTelegrams.Telegram
  end

  defmodule Server do
    use Protocols.ReqResServer, transport: TelegramTransport

    @impl true
    def init_session(_socket) do
      # a counter as the session state
      0
    end

    @impl true
    def handle_request(request, session) do
      alias ExampleTelegrams.Telegram1
      alias ExampleTelegrams.Telegram2

      case request do
        %Telegram1{} ->
          {:reply, %Telegram2{counter: session}, session + 1}
      end
    end

    @impl true
    def handle_session_error(reason) do
      IO.inspect(reason, label: "Client session failed")
      # called on parse errors, for logging, etc.
      :ok
    end
  end

  defmodule Client do
    use Protocols.ReqResClient, transport: TelegramTransport
  end

  test "request-response round trip" do
    alias ExampleTelegrams.Telegram1
    alias ExampleTelegrams.Telegram2

    {:ok, pid} = GenServer.start_link(Server, 0)

    port = GenServer.call(pid, :get_port)

    {:ok, conn} = TelegramTransport.connect({127, 0, 0, 1}, port, 1000)

    assert Client.request!(conn, %Telegram1{message: "Fo"}) ==
             %Telegram2{counter: 0}

    assert Client.request!(conn, %Telegram1{message: "Ba"}) ==
             %Telegram2{counter: 1}

    # TODO test errors
  end
end
