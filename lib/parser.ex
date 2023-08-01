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
    # calls f.(output, rest, ..args) => {:ok, ...}, {:error...}
    fmap(
      to_map,
      {&map_0/2, [{f, args}]}
    )
  end

  # defp return_0(bytes, v) do
  #   {:ok, v, bytes}
  # end

  # defp return(v) do
  #   prim(&return_0/2, [v])
  # end

  # def empty() do
  #   return(@nothing)
  # end

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

  @doc """
  For two parsers that return a list of values, concatenate the results of both.
  """
  def concat(left, right) when is_parser(left) and is_parser(right) do
    fmap(
      left,
      {&concat_0/2, [right]}
    )
  end

  defp choice_0(bytes, c1, cr) do
    case invoke(c1, bytes) do
      {:ok, output, rest} ->
        {:ok, output, rest}

      err ->
        case cr do
          [] -> err
          [c] -> invoke(c, bytes)
          [c1 | cr] -> choice_0(bytes, c1, cr)
        end
    end
  end

  defp choice_err(result, choices) do
    case result do
      # Note: include last reason because it might include the input (could be done nicer)
      {:error, reason} -> {:error, {:no_choices_matched, choices, reason}}
      ok -> ok
    end
  end

  def choice(choices) do
    [c1 | cr] = choices
    fmap(prim(&choice_0/3, [c1, cr]), {&choice_err/2, [choices]})
  end

  defp any_byte_string_00(bytes, count) do
    s = byte_size(bytes)

    cond do
      s < count ->
        :eof

      s == count ->
        {:ok, bytes, <<>>}

      true ->
        take = count
        p1 = :binary.part(bytes, {0, take})
        p2 = :binary.part(bytes, {take, s - take})
        {:ok, p1, p2}
    end
  end

  def any_byte_string(count) do
    prim(&any_byte_string_00/2, [count])
  end

  defp range_predicate_0(bytes, ok_set) do
    # Note: not very efficient; maybe some :binary.matches would be more efficient...?
    # !Enum.any?(bytes, fn b -> !Enum.member?(ok, set, b))
    if byte_size(bytes) == 0 do
      true
    else
      Enum.reduce_while(Range.new(0, byte_size(bytes) - 1), true, fn idx, acc ->
        if acc do
          {:cont, MapSet.member?(ok_set, :binary.at(bytes, idx))}
        else
          {:halt, false}
        end
      end)
    end
  end

  defp take_while_0(bytes, pred) do
    # Note: not very efficient; checks suffix again and again.
    if byte_size(bytes) == 0 do
      {:ok, <<>>, <<>>}
    else
      ok_part =
        Enum.reduce_while(Range.new(0, byte_size(bytes)), <<>>, fn len, acc ->
          start = :binary.part(bytes, {0, len})

          if pred.(start) do
            {:cont, start}
          else
            {:halt, acc}
          end
        end)

      rest = :binary.part(bytes, {byte_size(ok_part), byte_size(bytes) - byte_size(ok_part)})

      {:ok, ok_part, rest}
    end
  end

  def take_while(pred) do
    prim(&take_while_0/2, [pred])
  end

  defp range_predicate(range) do
    # range can be a Range, or any other Enum
    set = MapSet.new(range)

    {&range_predicate_0(&1, set), range}
  end

  defp and_max_0(bytes, pred, max) do
    res = byte_size(bytes) <= max && pred.(bytes)
    res
  end

  defp and_max(pred, max) do
    &and_max_0(&1, pred, max)
  end

  defp byte_string_verify_and_more(start, rest, pred, descr, min, max) do
    if pred.(start) do
      pred =
        if max != :infinity do
          and_max(pred, max - min)
        else
          pred
        end

      case invoke(take_while(pred), rest) do
        {:ok, more, rest} -> {:ok, start <> more, rest}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, {:not_in_range, descr, start}}
    end
  end

  defp byte_string_1(pred, descr, min, max) do
    map(
      any_byte_string(min),
      {&byte_string_verify_and_more/6, [pred, descr, min, max]}
    )
  end

  def byte_string(range, count_or_min_max) do
    {pred, descr} = range_predicate(range)

    {min, max} =
      if is_integer(count_or_min_max) do
        {count_or_min_max, count_or_min_max}
      else
        {count_or_min_max[:min], count_or_min_max[:max] || :infinity}
      end

    byte_string_1(pred, descr, min, max)
  end

  defp from_enc(bytes, rest, encoding) do
    case Codepagex.to_string(bytes, encoding) do
      {:ok, s} -> {:ok, s, rest}
      {:error, reason} -> {:error, {:not_in_encoding, encoding, bytes, reason}}
    end
  end

  def char_encoding(string_p, encoding) do
    map(string_p, {&from_enc/3, [encoding]})
  end

  defp label_0(return, label) do
    case return do
      {:error, reason} -> {:error, {label, reason}}
      other -> other
    end
  end

  def label(p, label) do
    fmap(
      p,
      {&label_0/2, [label]}
    )
  end

  defp const_0(read_bytes, rest, const_bytes) do
    if read_bytes == const_bytes do
      {:ok, @nothing, rest}
    else
      {:error, {:expected, const_bytes, read_bytes}}
    end
  end

  defp const_1(bytes) do
    map(any_byte_string(byte_size(bytes)), {&const_0/3, [bytes]})
  end

  defp prepend_ignore(input, p, ign) do
    case invoke(ign, input) do
      {:ok, _, rest} -> invoke(p, rest)
      err -> err
    end
  end

  defp append_ignore(input, p, ign) do
    case invoke(p, input) do
      {:ok, v, rest} ->
        case invoke(ign, rest) do
          {:ok, _, rest} -> {:ok, v, rest}
          err -> err
        end

      err ->
        err
    end
  end

  @doc """
  Expect bytes, before parsing with p.
  """
  def prepend_const(p, bytes) do
    prim(&prepend_ignore/3, [p, const_1(bytes)])
  end

  @doc """
  Expect bytes, after parsing with p.
  """
  def append_const(p, bytes) do
    prim(&append_ignore/3, [p, const_1(bytes)])
  end

  defp optional_0(bytes, option) do
    case invoke(option, bytes) do
      {:ok, output, rest} -> {:ok, output, rest}
      _ -> {:ok, nil, bytes}
    end
  end

  @doc """
  Results in nil if the given parser 'option' does not match.
  """
  def optional(option) when is_parser(option) do
    prim(&optional_0/2, [option])
  end

  defp tag_0(output, rest, tag) do
    {:ok, {tag, output}, rest}
  end

  def tag(to_tag, tag) do
    map(to_tag, {&tag_0/3, [tag]})
  end

  defp non_neg_integer_0(s, rest) do
    case Integer.parse(s) do
      {i, ""} -> {:ok, i, rest}
      {_i, _r} -> {:error, {:expected_int, s}}
      :error -> {:error, {:expected_int, s}}
    end
  end

  @digits ?0..?9

  def non_neg_integer(digits_or_min_max) do
    map(
      byte_string(@digits, digits_or_min_max),
      {&non_neg_integer_0/2, []}
    )
  end

  def structure_0(output, rest, struct, fields) do
    {:ok, Kernel.struct!(struct, Enum.zip(fields, output)), rest}
  end

  defp concat_rev(right, left), do: concat(left, right)

  def list(parsers) do
    # TODO: something more efficient?
    Enum.reduce(Enum.map(parsers, &wrap/1), &concat_rev/2)
  end

  def structure(struct, fields_parsers) do
    {fields, parsers} = Enum.unzip(fields_parsers)

    map(
      list(parsers),
      {&structure_0/4, [struct, fields]}
    )
  end

  defp wrap_0(output, rest) do
    wrapped = if output == @nothing, do: [], else: [output]
    {:ok, wrapped, rest}
  end

  def wrap(to_wrap) do
    map(to_wrap, {&wrap_0/2, []})
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
