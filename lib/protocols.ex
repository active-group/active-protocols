defmodule Active.Protocols do
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
    # :gen_tcp.timeout()
    @type tmo :: term

    @callback send(connection, data) :: :ok | {:error, atom}
    @callback recv(connection, tmo) :: {:ok, data} | {:error, atom}
    @callback close(connection) :: :ok

    defmacro __using__(_opts) do
      quote do
        @behaviour Transport
      end
    end
  end

  defmodule TCPTransport do
    @moduledoc """
    A behaviour for modules that adds the Transport behaviour using a Socket connection
    and a module with the Telegram behaviour to encode and decode binaries.

    ```
    use TCPTransport, telegrams: TelegramModule
    ```
    """

    defmacro __using__(opts) do
      quote do
        use Transport
        # import :erlang, only: [gen_tcp: 0]

        alias unquote(opts[:telegrams]), as: TG

        @min_length (case(TG.decode(<<>>)) do
                       {:need_more, n} -> n
                       _ -> 1
                     end)

        @impl Transport
        # @spec send(:gen_tcp.socket(), term) :: :ok | {:error, atom}
        def send(conn, telegram) do
          :gen_tcp.send(conn, TG.encode(telegram))
        end

        defp recv_cont(conn, acc, need, timeout) do
          case :gen_tcp.recv(conn, need, timeout) do
            {:ok, data} ->
              msg = acc <> :binary.list_to_bin(data)

              case TG.decode(msg) do
                {:ok, res} -> {:ok, res}
                {:need_more, n} -> recv_cont(conn, msg, n, timeout)
                {:error, reason} -> {:error, {:telegram_decode_failed, reason}}
              end

            {:error, reason} ->
              {:error, reason}
          end
        end

        @impl Transport
        # @spec send(:gen_tcp.socket(), :gen_tcp.timeout()) :: {:ok, term} | {:error, atom}
        def recv(conn, timeout) do
          # Note: the timeout may be 'applied' multiple times, i.e. it represents a minimum time before {:error, :timeout} is returned.
          recv_cont(conn, <<>>, @min_length, timeout)
        end

        @spec connect(:gen_tcp.address(), :gen_tcp.port(), :gen_tcp.timeout()) ::
                {:ok, :gen_tcp.socket()} | {:error, :timeout} | {:error, :inet.posix()}
        def connect(addr, port, timeout),
          do: :gen_tcp.connect(addr, port, [active: false], timeout)

        @impl Transport
        def close(socket) do
          :gen_tcp.close(socket)
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

        def request(conn, telegram, response_timeout) do
          case TR.send(conn, telegram) do
            {:error, reason} ->
              {:error, {:send_failed, reason}}

            :ok ->
              case TR.recv(conn, response_timeout) do
                {:error, reason} -> {:error, {:recv_failed, reason}}
                {:ok, response} -> {:ok, response}
              end
          end
        end

        def request!(conn, telegram, response_timeout) do
          # Note: Usually and error means the connection is unusable afterwards
          # (in the middle of a message is doesn't understand, etc).
          # Users should usually fail/reconnect. So this is handy for that.
          case request(conn, telegram, response_timeout) do
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
    @type socket_info :: term

    @callback init_session(pid, socket) :: session
    @callback handle_request(request, session) :: {:reply, response, session}
    @callback handle_session_error(term, socket_info) :: :ok

    defmodule State do
      defstruct [:port, :max_sessions]
    end

    defmacro __using__(opts) do
      quote do
        @behaviour ReqResServer

        use GenServer
        # import :erlang, only: [gen_tcp: 0]

        alias unquote(opts[:transport]), as: TR

        @impl GenServer
        def init(args) do
          port = args[:port]
          max_sessions = args[:max_sessions]
          # gen_tcp:address()
          bind_addr = args[:bind_address]

          # TOOD: add address/adapter to listen on
          case :gen_tcp.listen(port, active: false, ip: bind_addr) do
            {:error, reason} ->
              {:stop, {:listen_failed, reason}}

            {:ok, socket} ->
              {:ok, port} = :inet.port(socket)
              server = self()
              # possible supervisor options: :max_children
              {:ok, session_supervisor} = Task.Supervisor.start_link()

              {:ok, _pid} =
                Task.start_link(fn -> accept_loop(server, session_supervisor, socket) end)

              {:ok, %State{port: port, max_sessions: max_sessions}}
          end
        end

        @impl GenServer
        def handle_call(:get_port, _from, state), do: {:reply, state.port, state}

        @impl GenServer
        def handle_cast({:session_failed, reason, info}, state) do
          # Allow handle_session_error to change state?
          :ok = handle_session_error(reason, info)
          {:noreply, state}
        end

        defp accept_loop(server_pid, supervisor, listen_socket) do
          case :gen_tcp.accept(listen_socket) do
            {:ok, socket} ->
              # Note: we want to close connections (sessions) when the server stops, but not the other way round.

              {:ok, _pid} =
                Task.Supervisor.start_child(
                  supervisor,
                  fn -> run_session(server_pid, socket) end,
                  [:temporary]
                )

              # TODO: limit the number of active session? Stop accepting then or limit the supervisor?
              # if Enum.size(Task.Supervisor.children(supervisor)) < max_sessions ...  what could be the else here?
              accept_loop(server_pid, supervisor, listen_socket)

            {:error, reason} ->
              Process.exit(self(), reason)
          end
        end

        defp run_session(server_pid, socket) do
          case serve_client(socket, init_session(server_pid, socket)) do
            :ok ->
              nil

            {:error, reason} ->
              info = :inet.peername(socket)
              :ok = TR.close(socket)
              GenServer.cast(server_pid, {:session_failed, reason, info})
          end
        end

        defp serve_client(socket, session) do
          # TODO: configurable timeout?
          case TR.recv(socket, 10 * 1000) do
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
