defmodule ExampleTelegrams do
  defmodule Telegram1 do
    use Active.Telegram

    defstruct [:message]

    def decode(bytes) do
      case bytes do
        <<1, message::binary-size(2), rest::binary>> -> {:ok, %Telegram1{message: message}, rest}
        <<1, _::binary-size(1)>> -> :eof
        <<1>> -> :eof
        <<>> -> :eof
        _ -> {:error, :expected_1}
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
        <<2>> -> :eof
        <<>> -> :eof
        _ -> {:error, :expected_2}
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

    def decode(bytes), do: {:error, {:invalid_telegram, bytes}}

    def encode(_v), do: {:ok, <<42>>}
  end

  use Active.Telegram

  def decode(bytes) do
    case Telegram1.decode(bytes) do
      {:ok, result, rest} ->
        {:ok, result, rest}

      _err ->
        case Telegram2.decode(bytes) do
          {:ok, result, rest} ->
            {:ok, result, rest}

          err ->
            err
        end
    end
  end

  def encode(v) do
    case v do
      %Telegram1{} -> Telegram1.encode(v)
      %Telegram2{} -> Telegram2.encode(v)
      %InvalidTelegram{} -> InvalidTelegram.encode(v)
    end
  end
end
