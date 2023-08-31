defmodule Active.Telegram do
  @type telegram :: term

  # OPT: maybe make if {:eof, decoder_state} of 'continuation' to resume parsing after more bytes are received.

  @callback decode(nonempty_binary) :: {:ok, telegram, binary} | :eof | {:error, term}

  @callback encode(telegram) :: {:ok, nonempty_binary} | {:error, term}

  defmacro __using__(_opts) do
    quote do
      @behaviour Active.Telegram
    end
  end
end
