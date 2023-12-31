defmodule Active.Coding do
  alias Active.Parser, as: P

  alias Active.Formatter, as: F

  # Note: wanted to make it 'opaque', but dializer complains on user side then.
  @type t() :: {F.t(), P.t()}

  @type int_or_min_max ::
          non_neg_integer() | [{:min, non_neg_integer()} | {:max, non_neg_integer() | :infinity}]
  @type range :: [char] | Range.t() | Enum.t()

  @spec non_neg_integer(int_or_min_max) :: t()
  def non_neg_integer(digits_or_min_max) do
    {F.non_neg_integer(digits_or_min_max), P.non_neg_integer(digits_or_min_max)}
  end

  @spec byte_string(range, int_or_min_max) :: t()
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

  @spec structure(atom, [{atom, t}]) :: t
  def structure(struct, fields_codings) do
    {fields, codings} = Enum.unzip(fields_codings)
    {fs, ps} = Enum.unzip(codings)

    {F.unstruct(struct, Enum.zip(fields, fs)), P.structure(struct, Enum.zip(fields, ps))}
  end

  @doc """
  For codings then encode a byte string, resp. decode into a byte string, convert it according to the given 8bit-character encoding from/into a utf8 string (proper Elixir strings).
  """

  def char_encoding(string_c, encoding) do
    {string_f, string_p} = string_c
    {F.char_encoding(string_f, encoding), P.char_encoding(string_p, encoding)}
  end

  defmodule CharRange do
    def any, do: 0..255
    def digits, do: ?0..?9
    def ascii_printable, do: 32..126

    def except(base_range, exclude_char) do
      Enum.filter(base_range, fn c -> c != exclude_char end)
    end
  end

  @doc false
  # only for macro
  def formatter(coding) do
    {f, _} = coding
    f
  end

  @doc false
  # only for macro
  def parser(coding) do
    {_, p} = coding
    p
  end

  @doc false
  # only for tests.
  def encode(coding, value) do
    F.invoke(formatter(coding), value)
  end

  @doc false
  # only for tests.
  def decode(coding, binary) do
    P.invoke(parser(coding), binary)
  end

  defmacro defcoding(encoder_name, decoder_name, spec) do
    quote do
      require Active.Parser
      require Active.Formatter

      F.defformatter(unquote(encoder_name), Active.Coding.formatter(unquote(spec)))
      P.defparser(unquote(decoder_name), Active.Coding.parser(unquote(spec)))
    end
  end
end
