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
        @behaviour TCPServerProtocol

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
          # TODO: Use _transport.recv and .send and .close
          Active.TelegramTCPSocket.socket(ip_socket, telegrams)
        end

        apply(mod, :start_link, [telegram_socket, opts])
      end
    end
  end

  defmodule TCPServerRequestResponse do
    @moduledoc """
    use TCPServerRequestResponse, ...

    then

    {:ok, pid} = start_listener(name, address, port, idle_timeout, use_arg)

    stop_listener(name)

    get_port(name)

    use_arg is passed to init_session.
    """

    @type telegram :: term

    @type session :: term

    @callback init_session(Active.TelegramTCPSocket.t(), term) :: session

    @callback handle_request(session, telegram) ::
                {:reply, telegram, session} | {:noreply, session}

    @callback handle_error(session, term) :: :close | {:continue, session} | {:fail, term}

    defmacro __using__(opts) do
      quote do
        @behaviour TCPServerRequestResponse

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
      case Active.TelegramTCPSocket.recv(socket, timeout) do
        {:ok, request} ->
          case apply(module, :handle_request, [session, request]) do
            {:reply, response, session} ->
              Active.TelegramTCPSocket.send(socket, response)
              do_req_res_loop(session, module, socket, timeout)

            {:noreply, session} ->
              do_req_res_loop(session, module, socket, timeout)
          end

        {:error, :timeout} ->
          Active.TelegramTCPSocket.close(socket)
          nil

        # TODO: some handle_error callback for logging?
        {:error, reason} ->
          case apply(module, :handle_error, [session, reason]) do
            :close ->
              Active.TelegramTCPSocket.close(socket)
              nil

            {:continue, session} ->
              do_req_res_loop(session, module, socket, timeout)

            {:fail, reason} ->
              Active.TelegramTCPSocket.close(socket)
              Process.exit(self(), reason)
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
              {:ok, Active.TelegramTCPSocket.socket(ip_socket, telegrams())}

            {:error, reason} ->
              {:error, reason}
          end
        end

        def close(socket), do: Active.Protocols.TCPClientRequestResponse.do_close(socket)

        def request(socket, telegram, timeout),
          do: Active.Protocols.TCPClientRequestResponse.do_request(socket, telegram, timeout)
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

  defmodule UDPServerRequestResponse do
    # TODO: can have basically the same callbacks as TCPServerRequestResponse, without the session.
  end
end
