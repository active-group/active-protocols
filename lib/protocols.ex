defmodule Active.Protocols do
  @moduledoc """
  Utilities to implement communication protocols over the transport of telegrams.
  """

  defmodule TCPServerProtocol do
    @doc """
    Start a process that handles the give socket(), i.e. by calling recv/send in a loop.
    """
    @callback start_link((() -> Active.TelegramTCPSocket.t()), term) :: GenServer.on_start()

    defmacro __using__(opts) do
      quote do
        @behaviour Active.Protocols.TCPServerProtocol

        alias unquote(opts[:telegrams]), as: Telegrams

        _ =
          case unquote(opts[:telegrams]) do
            nil -> raise(ArgumentError, "Missing required telegrams option")
            _ -> nil
          end

        require Active.Protocols.TCPServerProtocol.RanchProtocol

        @spec start_listener(atom, :inet.socket_address(), :inet.port_number(), timeout, term) ::
                {:ok, pid} | {:error, term}
        def start_listener(name, bind_address, port, idle_session_timeout, init_arg) do
          # Note: By default the socket will be set to return binary data, with the options {active, false}, {packet, raw}, {reuseaddr, true} set

          transport_opts = [ip: bind_address, port: port]

          protocol_opts = [
            module: __MODULE__,
            telegrams: Telegrams,
            idle_timeout: idle_session_timeout,
            init_arg: init_arg
          ]

          :ranch.start_listener(
            name,
            :ranch_tcp,
            transport_opts,
            Active.Protocols.TCPServerProtocol.RanchProtocol,
            protocol_opts
          )
        end

        def stop_listener(name), do: :ranch.stop_listener(name)

        def get_port(name) do
          :ranch.get_port(name)
        end
      end
    end

    defmodule RanchProtocol do
      @behaviour :ranch_protocol

      def start_link(ref, _socket, _transport, opts) do
        mod = opts[:module]
        telegrams = opts[:telegrams]

        telegram_socket = fn ->
          # Note: handshake has to be done in the protocol process; otherwise it will hang.
          # Note: I think handshake will suceed with simple tcp as the transport.
          {:ok, ip_socket} = :ranch.handshake(ref)
          # TODO: Use _transport.recv and .send and .close?
          {:ok, remote} = :ranch_tcp.peername(ip_socket)
          Active.TelegramTCPSocket.socket(ip_socket, telegrams, remote)
        end

        apply(mod, :start_link, [telegram_socket, opts])
      end
    end
  end

  defmodule TCPServerRequestResponse do
    @moduledoc """
    use TCPServerRequestResponse, ...

    then

    {:ok, pid} = start_listener(name, address, port, idle_timeout, user_arg)

    stop_listener(name)

    get_port(name)

    user_arg is passed to init_session.
    """

    @type telegram :: term

    @type session :: term

    @callback init_session(Active.TelegramTCPSocket.t(), term) :: session

    @callback handle_request(session, telegram) ::
                {:reply, telegram, session} | {:noreply, session}

    @callback handle_error(session, term) :: :close | {:continue, session} | {:fail, term}

    defmacro __using__(opts) do
      quote do
        @behaviour Active.Protocols.TCPServerRequestResponse

        use TCPServerProtocol, telegrams: unquote(opts[:telegrams])

        @impl true
        def start_link(socket_f, opts) do
          # Note: opts: :idle_timeout and :init_session
          TCPServerRequestResponse.do_start_link(__MODULE__, socket_f, opts)
        end
      end
    end

    @doc false
    def do_start_link(module, socket_f, opts) do
      timeout = opts[:idle_timeout]
      init_arg = opts[:init_arg]

      Task.start_link(fn ->
        socket = socket_f.()
        session = apply(module, :init_session, [socket, init_arg])
        do_req_res_loop(session, module, socket, timeout)
      end)
    end

    defp do_req_res_loop(session, module, socket, timeout) do
      do_loop = fn session ->
        do_req_res_loop(session, module, socket, timeout)
      end

      do_handle_error = fn session, reason ->
        case apply(module, :handle_error, [session, reason]) do
          :close ->
            Active.TelegramTCPSocket.close(socket)
            nil

          {:continue, session} ->
            do_loop.(session)

          {:fail, reason} ->
            Active.TelegramTCPSocket.close(socket)
            Process.exit(self(), reason)
        end
      end

      case Active.TelegramTCPSocket.recv(socket, timeout) do
        {:ok, request} ->
          case apply(module, :handle_request, [session, request]) do
            {:reply, response, session} ->
              case Active.TelegramTCPSocket.send(socket, response) do
                :ok ->
                  do_loop.(session)

                {:error, reason} ->
                  do_handle_error.(session, reason)
              end

            {:noreply, session} ->
              do_loop.(session)
          end

        {:error, :timeout} ->
          Active.TelegramTCPSocket.close(socket)
          nil

        {:error, reason} ->
          do_handle_error.(session, reason)
      end
    end
  end

  defmodule UDPServer do
    # @type serve :: ((TelegramUDPSocket.t(), term) -> :ok)
    alias Active.TelegramUDPSocket

    def start_listener(address, port, telegrams, {init, init_args}, serve) do
      case :gen_udp.open(port, active: false, ip: address, reuseaddr: true, mode: :binary) do
        {:error, reason} ->
          {:error, {:error_open_udp_socket, reason}}

        {:ok, ip_socket} ->
          socket = TelegramUDPSocket.socket(ip_socket, telegrams)
          session = apply(init, [socket] ++ init_args)
          GenServer.start_link(__MODULE__, serve: serve, socket: socket, session: session)
      end
    end

    def get_port(pid) do
      # Note: fail if not ok, to match ranch api :-/
      {:ok, port} = GenServer.call(pid, :get_port)
      port
    end

    def stop_listener(pid) do
      GenServer.call(pid, :stop)
    end

    ####

    use GenServer

    @impl GenServer
    def init(args) do
      serve = args[:serve]
      socket = args[:socket]
      session = args[:session]
      {:ok, worker} = Task.start_link(fn -> serve.(socket, session) end)
      {:ok, %{socket: socket, worker: worker}}
    end

    @impl GenServer
    def handle_call(:get_port, _from, state) do
      {:reply, TelegramUDPSocket.get_port(state.socket), state}
    end

    @impl GenServer
    def handle_call(:stop, _from, state) do
      Process.exit(state.worker, :normal)
      TelegramUDPSocket.close(state.socket)
      {:reply, :ok, state}
    end
  end

  defmodule UDPServerRequestResponse do
    @moduledoc """
    use TCPServerRequestResponse, ...

    then

    {:ok, pid} = start_listener(address, port, user_arg)

    stop_listener(pid)

    get_port(pid)

    use_arg is passed to init_session.

    Note: there are no actual sessions, resp. only one session for the whole server.
    """

    @type telegram :: term

    @type session :: term

    @callback init_session(Active.TelegramTCPSocket.t(), term) :: session

    @callback handle_request(session, telegram) ::
                {:reply, telegram, session} | {:noreply, session}

    @callback handle_error(session, term) :: :close | {:continue, session} | {:fail, term}

    def do_serve(module, socket, session) do
      alias Active.TelegramUDPSocket

      do_loop = fn session ->
        do_serve(module, socket, session)
      end

      do_handle_error = fn session, reason ->
        case apply(module, :handle_error, [session, reason]) do
          :close ->
            Active.TelegramUDPSocket.close(socket)
            nil

          {:continue, session} ->
            do_loop.(session)

          {:fail, reason} ->
            Active.TelegramUDPSocket.close(socket)
            Process.exit(self(), reason)
        end
      end

      case TelegramUDPSocket.recv(socket, :infinity) do
        {:ok, {source_addr, source_port, request}} ->
          case apply(module, :handle_request, [session, request]) do
            {:reply, response, session} ->
              case TelegramUDPSocket.send(socket, source_addr, source_port, response) do
                :ok -> do_loop.(session)
                {:error, reason} -> do_handle_error.(session, reason)
              end

            {:noreply, session} ->
              do_loop.(session)
          end

        {:error, reason} ->
          do_handle_error.(session, reason)
      end
    end

    defmacro __using__(opts) do
      quote do
        def telegrams, do: unquote(opts[:telegrams])

        @behaviour Active.Protocols.UDPServerRequestResponse

        def start_listener(address, port, user_arg) do
          Active.Protocols.UDPServer.start_listener(
            address,
            port,
            telegrams(),
            {&init_session/2, [user_arg]},
            &Active.Protocols.UDPServerRequestResponse.do_serve(__MODULE__, &1, &2)
          )
        end

        def stop_listener(pid) do
          Active.Protocols.UDPServer.stop_listener(pid)
        end

        def get_port(pid) do
          Active.Protocols.UDPServer.get_port(pid)
        end
      end
    end
  end

  defmodule TCPClientRequestResponse do
    defmacro __using__(opts) do
      quote do
        def telegrams, do: unquote(opts[:telegrams])

        def connect(host, port, connect_timeout) do
          case :gen_tcp.connect(host, port, [active: false, mode: :binary], connect_timeout) do
            {:ok, ip_socket} ->
              {:ok, Active.TelegramTCPSocket.socket(ip_socket, telegrams(), {host, port})}

            {:error, reason} ->
              {:error, reason}
          end
        end

        def close(socket), do: Active.Protocols.TCPClientRequestResponse.do_close(socket)

        @doc """
        Send a telegram and immediately wait to receive a telegram.
        """
        def request(socket, telegram, timeout),
          do: Active.Protocols.TCPClientRequestResponse.do_request(socket, telegram, timeout)

        @doc """
        Send a telegram without waiting for a response.
        """
        def command(socket, telegram), do: Active.TelegramTCPSocket.send(socket, telegram)
      end
    end

    @doc false
    def do_close(socket) do
      Active.TelegramTCPSocket.close(socket)
    end

    @doc false
    def do_request(socket, telegram, timeout) do
      case Active.TelegramTCPSocket.send(socket, telegram) do
        {:error, :closed} ->
          {:error, {:send_failed, :closed}}

        {:error, reason} ->
          {:error, {:send_failed, reason}}

        :ok ->
          case Active.TelegramTCPSocket.recv(socket, timeout) do
            {:error, reason} -> {:error, {:recv_failed, reason}}
            {:ok, response} -> {:ok, response}
          end
      end
    end
  end

  defmodule UDPClientRequestResponse do
    @type telegram() :: any()

    @doc """
    Optional callback, called after every successfull receive of a telegram.
    """
    @callback monitor_inbound(:inet.socket_address(), :inet.port_number(), telegram()) :: :ok

    @doc """
    Optional callback, called after every successfull send of a telegram.
    """
    @callback monitor_outbound(:inet.socket_address(), :inet.port_number(), telegram()) :: :ok

    @optional_callbacks monitor_inbound: 3, monitor_outbound: 3

    defmacro __using__(opts) do
      quote do
        @behaviour Active.Protocols.UDPClientRequestResponse

        def telegrams, do: unquote(opts[:telegrams])

        # TODO: telegrams.t()?
        @type telegram() :: any()

        def connect(host, port) do
          case :gen_udp.open(0, active: false, mode: :binary) do
            {:error, reason} ->
              {:error, reason}

            {:ok, ip_socket} ->
              :ok = :gen_udp.connect(ip_socket, host, port)
              {:ok, Active.TelegramUDPSocket.socket(ip_socket, telegrams(), {host, port})}
          end
        end

        def close(socket), do: Active.Protocols.UDPClientRequestResponse.do_close(socket)

        @doc """
        Send a telegram and immediately wait to receive a telegram.
        """
        @spec request(Active.TelegramUDPSocket.t(), telegram(), any) ::
                {:ok, telegram()}
                | {:error, {:send_failed, term()}}
                | {:error, {:recv_failed, term()}}
        def request(socket, telegram, timeout),
          do:
            Active.Protocols.UDPClientRequestResponse.do_request(
              __MODULE__,
              socket,
              telegram,
              timeout
            )

        @doc """
        Send a telegram without waiting for a response.
        """
        @spec command(Active.TelegramUDPSocket.t(), telegram()) :: :ok | {:error, term()}
        def command(socket, telegram),
          do: Active.Protocols.UDPClientRequestResponse.do_send(__MODULE__, socket, telegram)
      end
    end

    @doc false
    def do_send(module, socket, telegram) do
      case Active.TelegramUDPSocket.send(socket, telegram) do
        :ok ->
          if function_exported?(module, :monitor_outbound, 3) do
            {host, port} = Active.TelegramUDPSocket.get_remote(socket)
            :ok = apply(module, :monitor_outbound, [host, port, telegram])
          end

          :ok

        {:error, err} ->
          {:error, err}
      end
    end

    @doc false
    def do_recv(module, socket, timeout) do
      case Active.TelegramUDPSocket.recv(socket, timeout) do
        {:ok, {from_host, from_port, response}} ->
          if function_exported?(module, :monitor_inbound, 3) do
            :ok = apply(module, :monitor_inbound, [from_host, from_port, response])
          end

          {:ok, {from_host, from_port, response}}

        {:error, err} ->
          {:error, err}
      end
    end

    @doc false
    def do_close(socket) do
      Active.TelegramUDPSocket.close(socket)
    end

    @doc false
    def do_request(module, socket, telegram, timeout) do
      case do_send(module, socket, telegram) do
        {:error, :closed} ->
          {:error, {:send_failed, :closed}}

        {:error, reason} ->
          {:error, {:send_failed, reason}}

        :ok ->
          case do_recv(module, socket, timeout) do
            {:error, reason} -> {:error, {:recv_failed, reason}}
            {:ok, {_from_host, _from_port, response}} -> {:ok, response}
          end
      end
    end
  end
end
