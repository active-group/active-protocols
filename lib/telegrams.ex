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

  defmodule Tagged do
    @enforce_keys [:tag, :value]
    defstruct [:tag, :value]

    @callback parse_tag(binary) :: {:ok, atom} | {:need_more, integer} | {:error, atom}

    @callback parse(atom, binary) :: {:ok, term} | {:need_more, integer} | {:error, atom}

    @callback unparse(atom, term) :: nonempty_binary

    def tagged(tag, v) do
      %Tagged{tag: tag, value: v}
    end

    def untag(v) do
      {v.tag, v.value}
    end

    def add_tag(tag, result) do
      case result do
        {:ok, v} -> {:ok, tagged(tag, v)}
        other -> other
      end
    end

    defmacro __using__(_opts) do
      quote do
        use T

        @impl T
        def parse(bytes) do
          case parse_tag(bytes) do
            {:ok, tag} -> Telegrams.Tagged.add_tag(tag, parse(tag, bytes))
            other -> other
          end
        end

        @impl T
        def unparse(value) do
          {tag, v} = Telegrams.Tagged.untag(value)
          unparse(tag, v)
        end
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
