defmodule Active.Telegram.Coding do
  @moduledoc "Codings that encode/decode a single value, can be used as the definition of a Telegram."
  defmacro __using__(opts) do
    quote do
      require Active.Coding

      Active.Coding.defcoding(:encode_, :decode_, unquote(opts[:coding]))

      use Active.Telegram

      @impl true
      def decode(binary) do
        case __MODULE__.decode_(binary) do
          {:ok, result, rest} ->
            {:ok, result, rest}

          :eof ->
            :eof

          {:error, e} ->
            {:error, e}
        end
      end

      @impl true
      def encode(term) do
        case __MODULE__.encode_(term) do
          {:ok, result} ->
            {:ok, result}

          {:error, e} ->
            {:error, e}
        end
      end
    end
  end
end
