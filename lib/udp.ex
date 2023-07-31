defmodule Active.TelegramUDPSocket do
  defstruct [:ip_socket, :tmodule]

  @type t() :: %__MODULE__{}

  def socket(ip_socket, telegram_module) do
    %__MODULE__{ip_socket: ip_socket, tmodule: telegram_module}
  end

  defp udp_send(ip_socket, tmodule, telegram, target \\ nil) do
    case apply(tmodule, :encode, [telegram]) do
      {:ok, bytes} ->
        # TODO: check for errors?
        :ok =
          case target do
            nil -> :gen_udp.send(ip_socket, bytes)
            {address, port} -> :gen_udp.send(ip_socket, address, port, bytes)
          end

        :ok

      {:error, err} ->
        {:error, err}
    end
  end

  defp udp_recv(ip_socket, tmodule, timeout) do
    # For UDP, we have to assume that a whole telegram is received in a single datagram.
    # The buffer is not used.
    case :gen_udp.recv(ip_socket, 0, timeout) do
      {:ok, v} ->
        # ignore 'ancdata'
        {address, port, bytes} =
          case v do
            {address, port, bytes} -> {address, port, bytes}
            {address, port, _ancdata, bytes} -> {address, port, bytes}
          end

        case apply(tmodule, :decode, [bytes]) do
          {:ok, telegram, ""} -> {:ok, {address, port, telegram}}
          {:ok, _telegram, _rest} -> {:error, {:decode_incomplete, bytes}}
          {:error, reason} -> {:error, {:decode_failed, reason}}
        end

      {:error, err} ->
        {:error, err}
    end
  end

  @doc """
  For connected sockets (i.e. clients)
  """
  @spec send(t(), term) :: :ok | {:error, term}
  def send(socket, telegram) do
    udp_send(socket.ip_socket, socket.tmodule, telegram)
  end

  @doc """
  For unconnected sockets (i.e. servers)
  """
  @spec send(t(), :inet.socket_address(), :inet.port_number(), term) :: :ok | {:error, term}
  def send(socket, address, port, telegram) do
    udp_send(socket.ip_socket, socket.tmodule, telegram, {address, port})
  end

  @spec recv(t(), timeout()) ::
          {:ok, :inet.socket_address(), :inet.port_number(), term} | {:error, term}
  def recv(socket, timeout) do
    # Note: update has a default timeout of 5 seconds. Failing the process if reached. Set to :infinity?
    # Note: this fails when the timeout is reached
    udp_recv(socket.ip_socket, socket.tmodule, timeout)
  end

  def close(socket) do
    :inet.close(socket.ip_socket)
  end

  def get_port(socket) do
    :inet.port(socket.ip_socket)
  end
end
