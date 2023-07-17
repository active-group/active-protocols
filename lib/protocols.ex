defmodule Active.Protocols do
  @moduledoc """
  Utilities to implement communication protocols over the transport of telegrams.
  """

  defmodule SocketTransport do
    @moduledoc """
    Functions to send telegrams over a socket.

    You can also use this module to get specialized send and recv functions:

    ```
    use SocketTransport, telegrams: TelegramModule
    ```
    """

    @type socket :: :gen_tcp.socket()
    @type telegram :: term()
    # t_module should have behaviour Telegram.T
    @type t_module :: module()

    def connect_opts(), do: [active: false]

    @spec send(socket, t_module, telegram) :: :ok | {:error, atom}
    def send(socket, module, telegram) do
      data = apply(module, :encode, [telegram])
      :gen_tcp.send(socket, data)
    end

    @spec recv(socket, t_module, timeout) :: {:ok, telegram} | {:error, atom}
    @doc "Note: the timeout may be 'applied' multiple times, i.e. it represents a minimum time before {:error, :timeout} is returned."
    def recv(socket, module, timeout) do
      min_length = get_min_length(module)
      recv_cont(socket, module, <<>>, min_length, timeout)
    end

    defp get_min_length(module) do
      case apply(module, :decode, [<<>>]) do
        {:need_more, n} -> n
        _ -> 1
      end
    end

    defp recv_cont(socket, module, acc, need, timeout) do
      case :gen_tcp.recv(socket, need, timeout) do
        {:ok, data} ->
          msg = acc <> :binary.list_to_bin(data)

          case apply(module, :decode, [msg]) do
            {:ok, res} -> {:ok, res}
            {:need_more, n} -> recv_cont(socket, module, msg, n, timeout)
            {:error, reason} -> {:error, {:telegram_decode_failed, reason}}
          end

        {:error, reason} ->
          {:error, reason}
      end
    end

    defmacro __using__(opts) do
      quote do
        alias unquote(opts[:telegrams]), as: TG

        @type socket :: :gen_tcp.socket()
        # TODO: TG.t()
        @type telegram :: term

        @spec send(socket, telegram) :: :ok | {:error, atom}
        def send(socket, telegram) do
          SocketTransport.send(socket, TG, telegram)
        end

        @spec recv(socket, timeout) :: {:ok, telegram} | {:error, atom}
        def recv(socket, timeout) do
          # Note: we could optimize determining the min_length at compile time.
          SocketTransport.recv(socket, TG, timeout)
        end
      end
    end
  end

  defmodule ReqResClient do
    @moduledoc """
    Functions to send requests and wait for responses over a socket.

    You can also use this module to inject a simplified API

    ```
    use ReqResClient, telegrams: TelegramModule
    ```
    """

    @type socket :: :gen_tcp.socket()
    @type telegram :: term()
    # t_module should have behaviour Telegram.T
    @type t_module :: module()

    @spec request(socket, t_module, telegram, timeout) ::
            {:ok, telegram} | {:error, {:send_failed, term}} | {:error, {:recv_failed, term}}
    def request(socket, module, telegram, response_timeout) do
      case SocketTransport.send(socket, module, telegram) do
        {:error, reason} ->
          {:error, {:send_failed, reason}}

        :ok ->
          case SocketTransport.recv(socket, module, response_timeout) do
            {:error, reason} -> {:error, {:recv_failed, reason}}
            {:ok, response} -> {:ok, response}
          end
      end
    end

    @spec connect(:inet.socket_address(), :inet.port_number(), timeout()) ::
            {:ok, socket} | {:error, :timeout} | {:error, :inet.posix()}
    def connect(addr, port, timeout) do
      # TODO: check arguments; this really like to throw einval
      opts = SocketTransport.connect_opts()
      :gen_tcp.connect(addr, port, opts, timeout)
    end

    defmacro __using__(opts) do
      quote do
        alias unquote(opts[:telegrams]), as: TG

        # Note: we could inject a specialized SocketTransport module here, for optimization.
        @type socket :: :gen_tcp.socket()
        # TODO: TG.t() ?
        @type telegram :: term()

        @spec request(socket, telegram, timeout) ::
                :ok | {:error, {:send_failed, term}} | {:error, {:recv_failed, term}}
        def request(socket, telegram, response_timeout) do
          ReqResClient.request(socket, TG, telegram, response_timeout)
        end

        @spec connect(:inet.socket_address(), :inet.port_number(), timeout()) ::
                {:ok, socket} | {:error, :timeout} | {:error, :inet.posix()}
        def connect(addr, port, timeout) do
          ReqResClient.connect(addr, port, timeout)
        end

        @spec close(socket) :: :ok
        def close(socket), do: :gen_tcp.close(socket)
      end
    end
  end

  defmodule ReqResServer do
    @moduledoc """
    A behaviour to inject the server side of a request-response
    based protocol over telegrams.

    ```
    use ReqResClient, telegrams: TelegramModule
    ```
    """

    @type telegram :: term
    @type request :: telegram
    @type response :: telegram
    @type session :: term
    @type socket :: :gen_tcp.socket()

    @type user_arg :: term

    @callback init_session(socket, user_arg) :: session

    @callback handle_request(request, session, user_arg) :: {:reply, response, session}

    @callback handle_session_error(socket, term) :: :ok

    def get_port(pid) do
      GenServer.call(pid, :get_port)
    end

    defmodule Server do
      use GenServer

      defmodule State do
        defstruct [:port]
      end

      @impl GenServer
      def init(args) do
        # t_module should be a SocketTransport
        t_module = args[:transport_module]
        # rrs_module should be a ReqResServer
        rrs_module = args[:module]
        port = args[:port] || 0
        bind_addr = args[:bind_address] || {0, 0, 0, 0}
        user_arg = args[:user_arg]
        idle_session_timeout = args[:session_timeout] || :infinity

        # TODO: check validity of args; esp. those that are only used later.

        case :gen_tcp.listen(port, active: false, ip: bind_addr) do
          {:error, reason} ->
            {:stop, {:listen_failed, reason}}

          {:ok, socket} ->
            {:ok, port} = :inet.port(socket)
            server = self()

            {:ok, session_supervisor} = Task.Supervisor.start_link()

            {:ok, _pid} =
              Task.start_link(fn ->
                accept_loop(
                  server,
                  session_supervisor,
                  rrs_module,
                  t_module,
                  socket,
                  idle_session_timeout,
                  user_arg
                )
              end)

            {:ok, %State{port: port}}
        end
      end

      @impl GenServer
      def handle_call(:get_port, _from, state), do: {:reply, state.port, state}

      defp accept_loop(
             server,
             session_supervisor,
             rrs_module,
             t_module,
             listen_socket,
             idle_session_timeout,
             user_arg
           ) do
        case :gen_tcp.accept(listen_socket) do
          {:ok, socket} ->
            # Note: we want to close connections (sessions) when the server stops, but not the other way round.
            {:ok, _pid} =
              Task.Supervisor.start_child(
                session_supervisor,
                fn ->
                  run_session(socket, rrs_module, t_module, idle_session_timeout, user_arg)
                end,
                restart: :temporary
              )

            accept_loop(
              server,
              session_supervisor,
              rrs_module,
              t_module,
              listen_socket,
              idle_session_timeout,
              user_arg
            )

          {:error, reason} ->
            Process.exit(self(), reason)
        end
      end

      defp run_session(socket, rrs_module, t_module, idle_timeout, user_arg) do
        session = apply(rrs_module, :init_session, [socket, user_arg])

        case serve_client(socket, session, rrs_module, t_module, idle_timeout, user_arg) do
          :ok ->
            nil

          :timeout ->
            :ok = :gen_tcp.close(socket)

          {:error, reason} ->
            apply(rrs_module, :handle_session_error, [socket, reason])
            :ok = :gen_tcp.close(socket)
        end
      end

      defp serve_client(socket, session, rrs_module, t_module, idle_timeout, user_arg) do
        # TODO: configurable timeout?

        case apply(t_module, :recv, [socket, idle_timeout]) do
          {:error, :closed} ->
            :ok

          {:error, :timeout} ->
            :timeout

          {:error, reason} ->
            {:error, {:receive_failed, reason}}

          {:ok, request} ->
            case apply(rrs_module, :handle_request, [request, session, user_arg]) do
              {:reply, response, session} ->
                case apply(t_module, :send, [socket, response]) do
                  :ok ->
                    serve_client(socket, session, rrs_module, t_module, idle_timeout, user_arg)

                  {:error, reason} ->
                    {:error, {:send_failed, reason}}
                end
            end
        end
      end
    end

    defmacro __using__(opts) do
      quote do
        @behaviour ReqResServer

        defmodule Transport do
          use SocketTransport, telegrams: unquote(opts[:telegrams])
        end

        @doc "Starts the server listening on the given address and port. Port can be 0 to pick an arbitrary free port."
        def start_link(bind_address, port, session_timeout, arg) do
          GenServer.start_link(Server,
            bind_address: bind_address,
            port: port,
            module: __MODULE__,
            user_arg: arg,
            transport_module: Transport,
            session_timeout: session_timeout
          )
        end

        def get_port(pid) do
          ReqResServer.get_port(pid)
        end
      end
    end
  end
end
