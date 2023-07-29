defmodule Active.Coding.DSL do
  alias Active.Parser, as: P

  alias Active.Formatter, as: F

  @opaque t() :: {F.t(), P.t()}

  @type int_or_min_max :: pos_integer | [{:min, pos_integer} | {:max, pos_integer | :infinity}]

  @spec empty() :: t()
  def empty(), do: {F.empty(), P.empty()}

  @spec non_neg_integer(t(), int_or_min_max) :: t()
  def non_neg_integer(c \\ empty(), digits_or_min_max) do
    {f, p} = c
    {F.non_neg_integer(f, digits_or_min_max), P.non_neg_integer(p, digits_or_min_max)}
  end

  @spec byte_string(t(), [char], int_or_min_max) :: t()
  def byte_string(c \\ empty(), range, count_or_min_max) do
    {f, p} = c
    {F.byte_string(f, range, count_or_min_max), P.byte_string(p, range, count_or_min_max)}
  end

  @spec label(t(), term) :: t()
  def label(c \\ empty(), label) do
    {f, p} = c
    {F.label(f, label), P.byte_string(p, label)}
  end

  @spec tagged(t(), term) :: t()
  def tagged(c \\ empty(), to_tag, tag) do
    {f, p} = c
    {to_tag_f, to_tag_p} = to_tag
    {F.untag(f, to_tag_f, tag), P.tag(p, to_tag_p, tag)}
  end

  @spec const(t(), binary) :: t()
  def const(c \\ empty(), binary) do
    {f, p} = c
    {F.const(f, binary), P.const(p, binary)}
  end

  @spec concat(t(), t()) :: t()
  def concat(left, right) do
    {left_f, left_p} = left
    {right_f, right_p} = right
    {F.concat(left_f, right_f), P.concat(left_p, right_p)}
  end

  @spec optional(t(), t()) :: t()
  def optional(c \\ empty(), option) do
    {f, p} = c
    {option_f, option_p} = option
    {F.optional(f, option_f), P.optional(p, option_p)}
  end

  @spec choice(t(), [t()]) :: t()
  def choice(c \\ empty(), choices) do
    {f, p} = c
    {choices_f, choices_p} = Enum.unzip(choices)
    {F.choice(f, choices_f), P.choice(p, choices_p)}
  end

  @spec structure(t, atom, %{atom => t}) :: t
  def structure(c \\ empty(), struct, fields_codings) do
    {f, p} = c
    {fields, codings} = Enum.unzip(fields_codings)
    {fs, ps} = Enum.unzip(codings)

    {F.unstruct(f, Enum.zip(fields, fs)), P.structure(p, struct, Enum.zip(fields, ps))}
  end

  defmacro defcoding(encoder_name, decoder_name, spec) do
    quote do
      require Active.Parser
      require Active.Formatter

      F.defformatter(unquote(encoder_name), elem(unquote(spec), 0))
      P.defparser(unquote(decoder_name), elem(unquote(spec), 1))
    end
  end
end

defmodule Active.Coding.Telegram do
  @moduledoc "Codings that encode/decode a single value, can be used as the definition of a Telegram."
  defmacro __using__(opts) do
    quote do
      require Active.Coding.DSL

      Active.Coding.DSL.defcoding(:encode_, :decode_, unquote(opts[:coding]))

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
