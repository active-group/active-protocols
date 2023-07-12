defmodule ExampleTelegrams do
  defmodule Telegram1 do
    use Telegrams.T

    defstruct [:message]

    def decode(bytes) do
      case bytes do
        <<1, message::binary-size(2)>> -> {:ok, %Telegram1{message: message}}
        <<1, _::binary-size(1)>> -> {:need_more, 1}
        <<1>> -> {:need_more, 2}
        <<>> -> {:need_more, 3}
        _ -> {:error, :decode_failed}
      end
    end

    def encode(v) do
      <<1>> <> v.message
    end
  end

  defmodule Telegram2 do
    use Telegrams.T

    defstruct [:counter]

    def decode(bytes) do
      case bytes do
        <<2, counter>> -> {:ok, %Telegram2{counter: counter}}
        <<2>> -> {:need_more, 1}
        <<>> -> {:need_more, 2}
        _ -> {:error, :decode_failed}
      end
    end

    def encode(v) do
      <<2, v.counter>>
    end
  end

  defmodule InvalidTelegram do
    # A telegram that can be send, but not be decoded.
    use Telegrams.T

    defstruct []

    def decode(_bytes), do: {:error, :decode_failed}

    def encode(_v), do: <<42>>
  end

  defmodule Telegram do
    use Telegrams.Modules

    def decode(bytes) do
      case bytes do
        # determine min of all?
        <<>> -> {:need_more, 1}
        <<1, _::binary>> -> Telegram1.decode(bytes)
        <<2, _::binary>> -> Telegram2.decode(bytes)
        <<cmd, _::binary>> -> {:error, {:unknown_command, cmd}}
      end
    end
  end
end
