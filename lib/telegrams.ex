defmodule Telegrams do
  defmodule T do
    @callback parse(binary) :: {:ok, term} | {:need_more, integer} | {:error, atom}

    @callback unparse(term) :: nonempty_binary()

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
        def unparse(value) do
          apply(value.__struct__, :unparse, [value])
        end
      end
    end
  end
end
