defmodule Active.Parser do
  # Parser is private
  @doc false
  defmodule Parser do
    defstruct [:f, :args]
  end

  @opaque t() :: %Parser{}

  defp prim(f, args), do: %Parser{f: f, args: args}
  defp prim(f), do: prim(f, [])

  defmacro is_parser(v) do
    quote do
      is_struct(unquote(v), Parser)
    end
  end

  @doc false
  # only for macro and tests.
  def invoke(p, bytes) when is_parser(p) and is_binary(bytes) do
    apply(p.f, [bytes] ++ p.args)
  end

  defp fmap(to_map, {f, args}) do
    # calls f.(return, ..args)
    fn bytes ->
      apply(f, [invoke(to_map, bytes)] ++ args)
    end
    |> prim
  end

  defp map(to_map, {f, args}) do
    # calls f.(output, rest, ..args)
    fmap(
      to_map,
      {fn result ->
         case result do
           {:ok, output, rest} -> apply(f, [output, rest] ++ args)
           other -> other
         end
       end, []}
    )
  end

  defp return(v) do
    fn bytes ->
      {:ok, v, bytes}
    end
    |> prim
  end

  def empty() do
    return([])
  end

  def concat(left, right) when is_parser(left) and is_parser(right) do
    fmap(
      left,
      {fn result ->
         case result do
           {:ok, output_l, rest} ->
             case invoke(right, rest) do
               {:ok, output_r, rest} ->
                 {:ok, output_l ++ output_r, rest}

               err ->
                 err
             end

           err ->
             err
         end
       end, []}
    )
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
    fn bytes ->
      choice_00(bytes, c1, cr)
    end
    |> prim
  end

  def choice(p \\ empty(), choices) do
    [c1 | cr] = choices
    concat(p, choice_0(c1, cr))
  end

  defp byte_string_0(range, count_or_min_max) when is_integer(count_or_min_max) do
    byte_string_0(range, min: count_or_min_max, max: count_or_min_max)
  end

  defp byte_string_0(range, min: min, max: max) do
    # TODO: check for range.
    fn bytes ->
      s = byte_size(bytes)

      cond do
        s < min ->
          :eof

        max == :infinity || s == max ->
          {:ok, [bytes], <<>>}

        true ->
          take = if s < max, do: s, else: max
          p1 = :binary.part(bytes, {0, take})
          p2 = :binary.part(bytes, {take, s - take})
          {:ok, [p1], p2}
      end
    end
    |> prim
  end

  def byte_string(p \\ empty(), range, count_or_min_max) do
    concat(p, byte_string_0(range, count_or_min_max))
  end

  def label(p \\ empty(), label) do
    fmap(
      p,
      {fn return ->
         case return do
           {:error, reason} -> {:error, {label, reason}}
           other -> other
         end
       end, []}
    )
  end

  defp const_0(const_bytes) do
    c_s = byte_size(const_bytes)

    fn bytes ->
      s = byte_size(bytes)

      cond do
        s >= c_s ->
          {part, rest} =
            cond do
              s == c_s -> {bytes, <<>>}
              true -> {:binary.part(bytes, 0, c_s), :binary.part(bytes, c_s, s - c_s)}
            end

          if part == const_bytes do
            {:ok, [], rest}
          else
            {:error, {:expected, const_bytes}}
          end

        true ->
          :eof
      end
    end
    |> prim
  end

  @doc """
  Expect bytes, but don't put them in the parser result.
  """
  def const(p \\ empty(), bytes) do
    concat(
      p,
      const_0(bytes)
    )
  end

  defp optional_0(option) do
    fn bytes ->
      case invoke(option, bytes) do
        :eof -> {:ok, [], bytes}
        {:error, _reason} -> {:ok, [], bytes}
        {:ok, output, rest} -> {:ok, output, rest}
      end
    end
    |> prim
  end

  def optional(p \\ empty(), option) do
    concat(p, optional_0(option))
  end

  defp tag_0(to_tag, tag) do
    map(
      to_tag,
      {fn output, rest ->
         {:ok, [{tag, output}], rest}
       end, []}
    )
  end

  def tag(p \\ empty(), to_tag, tag) do
    concat(p, tag_0(to_tag, tag))
  end

  def non_neg_integer(p \\ empty(), digits_or_min_max) do
    concat(
      p,
      map(
        byte_string([?0..?9], digits_or_min_max),
        {fn [s], rest ->
           case Integer.parse(s) do
             {i, ""} -> {:ok, [i], rest}
             {_i, _r} -> {:error, {:expected_int, s}}
             :error -> {:error, {:expected_int, s}}
           end
         end, []}
      )
    )
  end

  def structure_0(output, rest, struct, fields) do
    {:ok, Kernel.struct!(struct, Enum.zip(fields, output)), rest}
  end

  defp concat_rev(right, left), do: concat(left, right)

  def structure(p \\ empty(), struct, fields_parsers) do
    {fields, parsers} = Enum.unzip(fields_parsers)
    concat(p, map(Enum.reduce(parsers, &concat_rev/2), {&structure_0/4, [struct, fields]}))
  end

  @doc """
    Defines a parser with the given name and the given
    parser combinator. A parser is a function that takes a binary and returns `{:ok,
    output, rest_bytes}`, :eof or an error.
  """
  defmacro defparser(name, parser) do
    quote do
      def unquote(name)(bytes) do
        Active.Parser.invoke(unquote(parser), bytes)
      end
    end
  end
end
