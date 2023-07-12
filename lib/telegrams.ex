defmodule Active.Telegrams do
  defmodule T do
    @callback decode(binary) :: {:ok, term} | {:need_more, integer} | {:error, atom}

    @callback encode(term) :: nonempty_binary()

    defmacro __using__(_opts) do
      quote do
        @behaviour T
      end
    end
  end

  defmodule Modules do
    defmacro __using__(_opts) do
      quote do
        use T

        @impl T
        def encode(value) do
          apply(value.__struct__, :encode, [value])
        end
      end
    end
  end
end
