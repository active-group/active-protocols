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
          # TODO: use send_timeout?
          :gen_tcp.send(conn, TG.unparse(telegram))
        end

        defp recv_cont(conn, acc, need) do
          # TODO: timeouts, flags
          case :gen_tcp.recv(conn, need) do
            {:ok, data} ->
              msg = acc <> :binary.list_to_bin(data)

              case TG.parse(msg) do
                {:ok, res} -> {:ok, res}
                {:need_more, n} -> recv_cont(conn, msg, n)
                {:error, reason} -> {:error, {:parse_failed, reason}}
              end

            # TODO: timeout, closed?
            {:error, reason} ->
              {:error, reason}
          end
        end

        @impl Transport
        def recv(conn) do
          recv_cont(conn, <<>>, 1)
        end

        def connect(addr, port, timeout),
          # TODO: Opts
          do: :gen_tcp.connect(addr, port, [{:active, false}], timeout)
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

        def request(conn, telegram) do
          case TR.send(conn, telegram) do
            {:error, reason} ->
              {:error, {:send_failed, reason}}

            :ok ->
              case TR.recv(conn) do
                {:error, reason} -> {:error, {:recv_failed, reason}}
                {:ok, response} -> {:ok, response}
              end
          end
        end

        def request!(conn, telegram) do
          # Note: Usually and error means the connection is unusable afterwards
          # (in the middle of a message is doesn't understand, etc).
          # Users should usually fail/reconnect. So this is handy for that.
          case request(conn, telegram) do
            {:ok, response} -> response
            {:error, reason} -> throw(reason)
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
              {:stop, {:listen_failed, reason}}

            {:ok, socket} ->
              {:ok, port} = :inet.port(socket)
              server = self()
              # possible supervisor options: :max_children
              {:ok, session_supervisor} = Task.Supervisor.start_link()

              {:ok, _pid} =
                Task.start_link(fn -> accept_loop(server, session_supervisor, socket) end)

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

        defp accept_loop(server_pid, supervisor, listen_socket) do
          case :gen_tcp.accept(listen_socket) do
            {:ok, socket} ->
              # Note: we want to close connections (sessions) when the server stops, but not the other way round.
              # TODO: if we set max_children, start_child may return {:error, :max_children}; consider this? Maybe top accepting then
              {:ok, _pid} =
                Task.Supervisor.start_child(
                  supervisor,
                  fn -> run_session(server_pid, socket) end,
                  [:temporary]
                )

              accept_loop(server_pid, supervisor, listen_socket)

            {:error, reason} ->
              Process.exit(self(), reason)
          end
        end

        defp run_session(server_pid, socket) do
          case serve_client(socket, init_session(socket)) do
            :ok ->
              nil

            {:error, reason} ->
              GenServer.cast(server_pid, {:session_failed, reason})
          end
        end

        defp serve_client(socket, session) do
          case TR.recv(socket) do
            {:error, :closed} ->
              :ok

            {:error, reason} ->
              {:error, {:receive_failed, reason}}

            {:ok, request} ->
              case handle_request(request, session) do
                {:reply, response, session} ->
                  case TR.send(socket, response) do
                    :ok -> serve_client(socket, session)
                    {:error, reason} -> {:error, {:send_failed, reason}}
                  end
              end
          end
        end
      end
    end
  end
end
