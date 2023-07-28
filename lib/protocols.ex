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

        def get_port(name) do
          :ranch.get_port(name)
        end
      end
    end

    defmodule RanchProtocol do
      @behaviour :ranch_protocol

      def start_link(ref, _transport, opts) do
        mod = opts[:module]
        telegrams = opts[:telegrams]

        telegram_socket = fn ->
          # Note: handshake has to be done in the protocol process; otherwise it will hang.
          # Note: I think handshake will suceed with simple tcp as the transport.
          {:ok, ip_socket} = :ranch.handshake(ref)
          Active.TelegramTCPSocket.socket(ip_socket, telegrams)
        end

        apply(mod, :start_link, [telegram_socket, opts])
      end
    end
  end

  defmodule TCPServerRequestResponse do
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

  defmodule UDPServerRequestResponse do
    # TODO: can have basically the same callbacks as TCPServerRequestResponse, without the session.
  end
end
