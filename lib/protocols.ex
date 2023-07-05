defmodule Protocols do
  @moduledoc """
  Utilities to implement communication protocols over the transport of telegrams.
  """

  defmodule Transport do
    @moduledoc """
    A behaviour for modules that can send and receive some
    pieces of data over some kind of connection.
    """
    @type connection :: term
    @type data :: term

    @callback send(connection, data) :: :ok | {:error, atom}
    @callback recv(connection) :: {:ok, data} | {:error, atom}

    defmacro __using__(_opts) do
      quote do
        @behaviour Transport
      end
    end
  end

  defmodule TCPTransport do
    @moduledoc """
    A behaviour for modules that adds the Transport behaviour using a Socket connection
    and a module with the Telegram behaviour to parse and unparse binaries.

    ```
    use TCPTransport, telegrams: TelegramModule
    ```
    """

    defmacro __using__(opts) do
      quote do
        use Transport

        alias unquote(opts[:telegrams]), as: TG

        # TODO: Take a min-telegram-length for more efficient first recv?

        @impl Transport
        def send(conn, telegram) do
          bytes = TG.unparse(telegram)
          # TODO: use send_timeout?
          case :gen_tcp.send(conn, bytes) do
            :ok -> :ok
            {:error, reason} -> {:error, reason}
          end
        end

        defp recv_cont(conn, acc, need) do
          # TODO: timeouts, flags
          case :gen_tcp.recv(conn, need) do
            {:ok, data} ->
              msg = acc <> :binary.list_to_bin(data)

              case TG.parse(msg) do
                {:ok, res} -> {:ok, res}
                {:need_more, n} -> recv_cont(conn, msg, n)
                {:error, reason} -> {:error, reason}
              end

            {:error, reason} ->
              {:error, reason}
          end
        end

        @impl Transport
        def recv(conn) do
          recv_cont(conn, <<>>, 1)
        end

        def connect(addr, port, timeout) do
          # TODO: Opts
          case :gen_tcp.connect(addr, port, [{:active, false}], timeout) do
            {:error, reason} -> {:error, reason}
            {:ok, socket} -> {:ok, socket}
          end
        end
      end
    end
  end

  defmodule ReqResClient do
    @moduledoc """
    A behaviour for modules to act as a client module in a request-response based protocol, given a Transport module.

    ```
    use ReqResClient, transport: MyTransportModule
    ```
    """
    defmacro __using__(opts) do
      quote do
        alias unquote(opts[:transport]), as: TR

        def request!(conn, telegram) do
          case TR.send(conn, telegram) do
            :ok ->
              case TR.recv(conn) do
                {:ok, response} -> response
                # TODO: add 'receive failed'?
                {:error, reason} -> throw(reason)
              end

            # TODO: add 'send failed'?
            {:error, reason} ->
              throw(reason)
          end
        end
      end
    end
  end

  defmodule ReqResServer do
    @moduledoc """
    A GenServer behaviour for modules to act as a server module in a request-response
    based protocol, given a Transport module.

    ```
    use ReqResClient, transport: MyTransportModule
    ```
    """

    @type request :: term
    @type response :: term
    @type session :: term
    # :inet.socket something
    @type socket :: term

    @callback init_session(socket) :: session
    @callback handle_request(request, session) :: {:reply, response, session}
    # TODO: some info about client? callback or message?
    @callback handle_session_error(term) :: :ok

    defmodule State do
      defstruct [:port]
    end

    defmacro __using__(opts) do
      # TODO: ensure opts[:transport] is set, and is a module implementing Transport?
      quote do
        @behaviour ReqResServer

        use GenServer

        alias unquote(opts[:transport]), as: TR

        @impl GenServer
        def init(port) do
          # TOOD: other Opts for listen?
          case :gen_tcp.listen(port, [{:active, false}]) do
            {:error, reason} ->
              {:stop, reason}

            {:ok, socket} ->
              {:ok, port} = :inet.port(socket)
              server = self()
              {:ok, _pid} = Task.start_link(fn -> accept_loop(server, socket) end)
              {:ok, %State{port: port}}
          end
        end

        @impl GenServer
        def handle_call(:get_port, _from, state), do: {:reply, state.port, state}

        @impl GenServer
        def handle_cast({:session_failed, reason}, state) do
          :ok = handle_session_error(reason)
          {:noreply, state}
        end

        defp accept_loop(server_pid, listen_socket) do
          case :gen_tcp.accept(listen_socket) do
            {:ok, socket} ->
              # TODO: link it only in one direction (don't fail server when session fails)
              {:ok, _pid} = Task.start_link(fn -> run_session(server_pid, socket) end)
              accept_loop(server_pid, listen_socket)

            {:error, reason} ->
              # TODO: proper way to exit?
              throw(reason)
          end
        end

        defp run_session(server_pid, socket) do
          case serve_client(socket, init_session(socket)) do
            :ok ->
              nil

            {:error, reason} ->
              GenServer.cast(server_pid, {:session_failed, reason})
          end

          :gen_tcp.close(socket)
        end

        defp serve_client(socket, session) do
          case TR.recv(socket) do
            {:error, :closed} ->
              :ok

            {:error, reason} ->
              {:error, reason}

            {:ok, request} ->
              case handle_request(request, session) do
                {:reply, response, session} ->
                  case TR.send(socket, response) do
                    :ok -> serve_client(socket, session)
                    {:error, reason} -> {:error, reason}
                  end
              end
          end
        end
      end
    end
  end
end
