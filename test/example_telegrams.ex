defmodule ExampleTelegrams do
  defmodule Telegram1 do
    use Active.Telegram

    defstruct [:message]

    def decode(bytes) do
      case bytes do
        <<1, message::binary-size(2), rest::binary>> -> {:ok, %Telegram1{message: message}, rest}
        <<1, _::binary-size(1)>> -> {:error, :eof}
        <<1>> -> {:error, :eof}
        <<>> -> {:error, :eof}
        _ -> {:error, :decode_failed}
      end
    end

    def encode(v) do
      {:ok, <<1>> <> v.message}
    end
  end

  defmodule Telegram2 do
    use Active.Telegram

    defstruct [:counter]

    def decode(bytes) do
      case bytes do
        <<2, counter, rest::binary>> -> {:ok, %Telegram2{counter: counter}, rest}
        <<2>> -> {:error, :eof}
        <<>> -> {:error, :eof}
        _ -> {:error, :decode_failed}
      end
    end

    def encode(v) do
      {:ok, <<2, v.counter>>}
    end
  end

  defmodule InvalidTelegram do
    # A telegram that can be send, but not be decoded.
    use Active.Telegram

    defstruct []

    def decode(_bytes), do: {:error, :decode_failed}

    def encode(_v), do: {:ok, <<42>>}
  end
end
