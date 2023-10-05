defmodule Active.TelegramTCPSocket do
  defstruct [:agent, :ip_socket, :tmodule, :remote]

  @type t() :: %__MODULE__{}

  defmodule State do
    defstruct [:buffer]
  end

  def socket(ip_socket, telegram_module, remote) do
    {:ok, pid} = Agent.start_link(fn -> %State{buffer: <<>>} end)
    %__MODULE__{agent: pid, ip_socket: ip_socket, tmodule: telegram_module, remote: remote}
  end

  defp tcp_send(ip_socket, tmodule, telegram) do
    case apply(tmodule, :encode, [telegram]) do
      {:ok, bytes} ->
        case :gen_tcp.send(ip_socket, bytes) do
          # error: e.g. socket closed.
          {:error, reason} -> {:error, reason}
          :ok -> :ok
        end

      {:error, err} ->
        {:error, err}
    end
  end

  defp tcp_recv_bytes(ip_socket, length, timeout) do
    :gen_tcp.recv(ip_socket, length, timeout)
  end

  # Timeout may be applied multiple times; so is not a hard guarantee.
  defp tcp_recv_loop(ip_socket, tmodule, state, timeout) do
    # try parse current buffer
    case apply(tmodule, :decode, [state.buffer]) do
      {:ok, telegram, rest} ->
        # Success; return telegram and take rest as new buffer.
        {{:ok, telegram}, %{state | buffer: rest}}

      :eof ->
        # Need more data
        case tcp_recv_bytes(ip_socket, 0, timeout) do
          {:ok, bytes} ->
            tcp_recv_loop(ip_socket, tmodule, %{state | buffer: state.buffer <> bytes}, timeout)

          {:error, :timeout} ->
            {{:error, :timeout}, state}

          {:error, reason} ->
            {{:error, reason}, state}
        end

      {:error, reason} ->
        {{:error, {:decode_failed, reason}}, state}
    end
  end

  defp tcp_recv(ip_socket, tmodule, state, timeout) do
    tcp_recv_loop(ip_socket, tmodule, state, timeout)
  end

  @spec send(t(), term) :: :ok | {:error, term}
  def send(socket, telegram) do
    tcp_send(socket.ip_socket, socket.tmodule, telegram)
  end

  @spec recv(t(), timeout()) :: {:ok, term} | {:error, :timeout} | {:error, term}
  def recv(socket, timeout) do
    Agent.get_and_update(
      socket.agent,
      &tcp_recv(socket.ip_socket, socket.tmodule, &1, timeout),
      :infinity
    )
  end

  def close(socket) do
    :inet.close(socket.ip_socket)
  end

  @doc """
  Remote {address, port}.
  """
  def get_remote(socket) do
    socket.remote
  end
end
