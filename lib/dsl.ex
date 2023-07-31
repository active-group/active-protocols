defmodule Active.Coding.DSL do
  alias Active.Parser, as: P

  alias Active.Formatter, as: F

  @opaque t() :: {F.t(), P.t()}

  @type int_or_min_max :: pos_integer | [{:min, pos_integer} | {:max, pos_integer | :infinity}]

  @spec non_neg_integer(int_or_min_max) :: t()
  def non_neg_integer(digits_or_min_max) do
    {F.non_neg_integer(digits_or_min_max), P.non_neg_integer(digits_or_min_max)}
  end

  @spec byte_string([char], int_or_min_max) :: t()
  def byte_string(range, count_or_min_max) do
    {F.byte_string(range, count_or_min_max), P.byte_string(range, count_or_min_max)}
  end

  @spec label(t(), term) :: t()
  def label(c, label) do
    {f, p} = c
    {F.label(f, label), P.label(p, label)}
  end

  @spec tagged(t(), term) :: t()
  def tagged(to_tag, tag) do
    {to_tag_f, to_tag_p} = to_tag
    {F.untag(to_tag_f, tag), P.tag(to_tag_p, tag)}
  end

  @spec append_const(t(), binary) :: t()
  def append_const(c, binary) do
    {f, p} = c
    {F.append_const(f, binary), P.append_const(p, binary)}
  end

  @spec prepend_const(t(), binary) :: t()
  def prepend_const(c, binary) do
    {f, p} = c
    {F.prepend_const(f, binary), P.prepend_const(p, binary)}
  end

  @spec list([t()]) :: t()
  def list(codings) do
    {fs, ps} = Enum.unzip(codings)
    {F.list(fs), P.list(ps)}
  end

  @spec optional(t()) :: t()
  def optional(option) do
    {option_f, option_p} = option
    {F.optional(option_f), P.optional(option_p)}
  end

  @spec choice([t()]) :: t()
  def choice(choices) do
    {choices_f, choices_p} = Enum.unzip(choices)
    {F.choice(choices_f), P.choice(choices_p)}
  end

  @spec structure(atom, %{atom => t}) :: t
  def structure(struct, fields_codings) do
    {fields, codings} = Enum.unzip(fields_codings)
    {fs, ps} = Enum.unzip(codings)

    {F.unstruct(Enum.zip(fields, fs)), P.structure(struct, Enum.zip(fields, ps))}
  end

  @doc false
  # only for tests.
  def encode(coding, value) do
    {f, _} = coding
    F.invoke(f, value)
  end

  @doc false
  # only for tests.
  def decode(coding, binary) do
    {_, p} = coding
    P.invoke(p, binary)
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
