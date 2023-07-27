defmodule Active.Telegram do
  @type telegram :: term

  @callback decode(nonempty_binary) :: {:ok, telegram, binary} | {:error, :eof} | {:error, term}

  @callback encode(telegram) :: {:ok, nonempty_binary} | {:error, term}

  defmacro __using__(_opts) do
    quote do
      @behaviour Active.Telegram
    end
  end
end
