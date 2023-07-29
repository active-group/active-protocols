defmodule Active.Parser do
  # Parser is private
  @doc false
  defmodule Parser do
    defstruct [:f, :args]
  end

  @opaque t() :: %Parser{}

  defp prim(f, args), do: %Parser{f: f, args: args}

  defmacro is_parser(v) do
    quote do
      is_struct(unquote(v), Parser)
    end
  end

  defmodule Nothing do
  end

  # any globally distinct value
  @nothing Nothing

  @doc false
  # only for macro and tests.
  def invoke(p, bytes) when is_parser(p) and is_binary(bytes) do
    apply(p.f, [bytes] ++ p.args)
  end

  defp fmap_0(bytes, to_map, {f, args}) do
    apply(f, [invoke(to_map, bytes)] ++ args)
  end

  defp fmap(to_map, {f, args}) do
    # calls f.(return, ..args)
    prim(&fmap_0/3, [to_map, {f, args}])
  end

  defp map_0(result, {f, args}) do
    case result do
      {:ok, output, rest} -> apply(f, [output, rest] ++ args)
      other -> other
    end
  end

  defp map(to_map, {f, args}) do
    # calls f.(output, rest, ..args)
    fmap(
      to_map,
      {&map_0/2, [{f, args}]}
    )
  end

  defp return_0(bytes, v) do
    {:ok, v, bytes}
  end

  defp return(v) do
    prim(&return_0/2, [v])
  end

  def empty() do
    return(@nothing)
  end

  defp concat_0(result, right) do
    case result do
      {:ok, output_l, rest} ->
        case invoke(right, rest) do
          {:ok, output_r, rest} ->
            output =
              cond do
                output_l == @nothing -> output_r
                output_r == @nothing -> output_l
                true -> output_l ++ output_r
              end

            {:ok, output, rest}

          err ->
            err
        end

      err ->
        err
    end
  end

  def concat(left, right) when is_parser(left) and is_parser(right) do
    cond do
      left == empty() ->
        right

      right == empty() ->
        left

      true ->
        fmap(
          left,
          {&concat_0/2, [right]}
        )
    end
  end

  defp choice_00(bytes, c1, cr) do
    case invoke(c1, bytes) do
      {:ok, output, rest} ->
        {:ok, output, rest}

      err ->
        case cr do
          [] -> err
          [c] -> invoke(c, bytes)
          [c1 | cr] -> choice_00(bytes, c1, cr)
        end
    end
  end

  defp choice_0(c1, cr) do
    prim(&choice_00/3, [c1, cr])
  end

  def choice(p \\ empty(), choices) do
    [c1 | cr] = choices
    concat(p, choice_0(c1, cr))
  end

  defp any_byte_string_00(bytes, min, max) do
    s = byte_size(bytes)

    cond do
      s < min ->
        :eof

      max == :infinity || s == max ->
        {:ok, bytes, <<>>}

      true ->
        take = if s < max, do: s, else: max
        p1 = :binary.part(bytes, {0, take})
        p2 = :binary.part(bytes, {take, s - take})
        {:ok, p1, p2}
    end
  end

  defp any_byte_string_0(count_or_min_max) when is_integer(count_or_min_max) do
    any_byte_string_0(min: count_or_min_max, max: count_or_min_max)
  end

  defp any_byte_string_0(min: min, max: max) do
    prim(&any_byte_string_00/3, [min, max])
  end

  def any_byte_string(p \\ empty(), count_or_min_max) do
    concat(p, any_byte_string_0(count_or_min_max))
  end

  def byte_string(p \\ empty(), range, count_or_min_max) do
    # TODO: check for range.
    any_byte_string(p, count_or_min_max)
  end

  defp label_0(return, label) do
    case return do
      {:error, reason} -> {:error, {label, reason}}
      other -> other
    end
  end

  def label(p \\ empty(), label) do
    fmap(
      p,
      {&label_0/2, [label]}
    )
  end

  defp const_0(read_bytes, rest, const_bytes) do
    if read_bytes == const_bytes do
      {:ok, @nothing, rest}
    else
      {:error, {:expected, const_bytes}}
    end
  end

  @doc """
  Expect bytes, but don't generate a parser result. Cannot be used on its own.
  """
  def const(p \\ empty(), bytes) do
    concat(
      p,
      map(any_byte_string(byte_size(bytes)), {&const_0/3, [bytes]})
    )
  end

  defp optional_0(bytes, option) do
    case invoke(option, bytes) do
      {:ok, output, rest} -> {:ok, output, rest}
      _ -> {:ok, nil, bytes}
    end
  end

  @doc """
  Parses nil if the given parser 'option' does not match.
  """
  def optional(p \\ empty(), option) when is_parser(option) do
    concat(p, prim(&optional_0/2, [option]))
  end

  defp tag_0(output, rest, tag) do
    {:ok, {tag, output}, rest}
  end

  def tag(p \\ empty(), to_tag, tag) do
    concat(p, map(to_tag, {&tag_0/3, [tag]}))
  end

  defp non_neg_integer_0(s, rest) do
    case Integer.parse(s) do
      {i, ""} -> {:ok, i, rest}
      {_i, _r} -> {:error, {:expected_int, s}}
      :error -> {:error, {:expected_int, s}}
    end
  end

  @digits [?0..?9]
  def non_neg_integer(p \\ empty(), digits_or_min_max) do
    concat(
      p,
      map(
        byte_string(@digits, digits_or_min_max),
        {&non_neg_integer_0/2, []}
      )
    )
  end

  def structure_0(output, rest, struct, fields) do
    {:ok, Kernel.struct!(struct, Enum.zip(fields, output)), rest}
  end

  defp concat_rev(right, left), do: concat(left, right)

  def list(p \\ empty(), parsers) do
    # TODO: something more efficient?
    concat(p, Enum.reduce(Enum.map(parsers, &wrap/1), &concat_rev/2))
  end

  def structure(p \\ empty(), struct, fields_parsers) do
    {fields, parsers} = Enum.unzip(fields_parsers)

    concat(
      p,
      map(
        list(parsers),
        {&structure_0/4, [struct, fields]}
      )
    )
  end

  defp wrap_0(output, rest) do
    wrapped = if output == @nothing, do: [], else: [output]
    {:ok, wrapped, rest}
  end

  def wrap(p \\ empty(), to_wrap) do
    concat(p, map(to_wrap, {&wrap_0/2, []}))
  end

  @doc """
    Defines a parser with the given name and the given
    parser combinator. A parser is a function that takes a binary and returns `{:ok,
    output, rest_bytes}`, :eof or an error.
  """
  defmacro defparser(name, parser) do
    quote do
      def unquote(name)(bytes) do
        # add check that throws if @nothing would be the result?
        Active.Parser.invoke(unquote(parser), bytes)
      end
    end
  end
end
