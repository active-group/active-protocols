defmodule Active.Formatter do
  # Fmt is private
  @doc false
  defmodule Fmt do
    defstruct [:f]
  end

  @opaque t() :: %Fmt{}

  defmacro is_format(v) do
    quote do
      is_struct(Fmt, unquote(v))
    end
  end

  # only for macro and tests.
  @doc false
  def invoke(fmt, input) do
    apply(fmt.f, [input])
  end

  @spec prim(([term] -> {:ok, binary, [term]} | {:error, term})) :: t()
  defp prim(f) do
    %Fmt{f: f}
  end

  ############################################################

  def map(fmt, {f, args}) do
    fn lst ->
      case invoke(fmt, lst) do
        {:ok, b, rest} -> {:ok, apply(f, [b] ++ args), rest}
        err -> err
      end
    end
    |> prim
  end

  def fmap(fmt, {f, args}) do
    fn lst ->
      case invoke(fmt, lst) do
        {:ok, b, rest} -> apply(f, [b, rest] ++ args)
        err -> err
      end
    end
    |> prim
  end

  defp return(v) do
    fn lst -> {:ok, v, lst} end
    |> prim
  end

  # def error(_fmt, e) do
  #   fn lst -> {:error, e} end
  # end

  # def map1(fmt, {f, args}) do
  #   fn [x | more] ->
  #     case fmt.([x]) do
  #       {:ok, b, rest} -> {:ok, apply(f, [b] ++ args), rest}
  #       err -> err
  #     end
  #   end
  # end

  def empty(), do: return(<<>>)

  ############################################################

  defp fmap1_0(prev, rest, f, args) do
    case rest do
      [] ->
        {:error, :eof}

      [v | rest] ->
        case apply(f, [v] ++ args) do
          {:ok, x} -> {:ok, prev <> x, rest}
          err -> err
        end
    end
  end

  defp fmap1(fmt, {f, args}) do
    fmap(fmt, {&fmap1_0/4, [f, args]})
  end

  ############################################################

  defp concat_0(left_res, rest, right) do
    case invoke(right, rest) do
      {:ok, right_res, rest} ->
        {:ok, left_res <> right_res, rest}

      err ->
        err
    end
  end

  def concat(left, right) do
    fmap(left, {&concat_0/3, [right]})
  end

  defp choice_0(prev, rest, c1, cr) do
    case invoke(c1, rest) do
      {:ok, result, rest} ->
        {:ok, prev <> result, rest}

      err ->
        case cr do
          [] -> err
          [c1 | cr] -> choice_0(prev, rest, c1, cr)
        end
    end
  end

  # TODO: rename to either?
  def choice(fmt \\ empty(), choices) do
    # when length(choices) >= 2
    case choices do
      [c1 | cr] -> fmap(fmt, {&choice_0/4, [c1, cr]})
    end
  end

  defp non_neg_integer_0(v, min, max) do
    # TODO: check if v is integer, and in range, add padding (option if '0' or ' '? front or back?), etc.
    if is_integer(v) do
      {:ok, Integer.to_string(v)}
    else
      {:error, {:integer_expected, v}}
    end
  end

  @doc """
  Formats a non negative integer into decimal digits. Leading 0s are added if
  the number would not have the given minimal number of digits. Results in
  an error if it would require more digits than the given maximum.
  """
  def non_neg_integer(fmt \\ empty(), digits_or_min_max)

  def non_neg_integer(fmt, digits_or_min_max) when is_integer(digits_or_min_max) do
    non_neg_integer(fmt, min: digits_or_min_max, max: digits_or_min_max)
  end

  def non_neg_integer(fmt, min: min) do
    non_neg_integer(fmt, min: min, max: :infinity)
  end

  def non_neg_integer(fmt, min: min, max: max) do
    fmap1(fmt, {&non_neg_integer_0/3, [min, max]})
  end

  defp ascii_string_0(s, range, min, max) do
    # TODO: need to convert to ascii?
    # TODO: check it's in the range, not too long; pad with ' ' if too short? (option if front or back?)
    if is_binary(s) do
      {:ok, s}
    else
      {:error, {:string_expected, s}}
    end
  end

  # def ascii_char(ranges), do: nil
  @spec ascii_string(
          t(),
          [char],
          pos_integer() | [{:min, non_neg_integer()} | {:max, pos_integer()}]
        ) :: t()
  def ascii_string(fmt \\ empty(), range, count_or_min_max)

  def ascii_string(fmt, range, count_or_min_max) when is_integer(count_or_min_max) do
    ascii_string(fmt, min: count_or_min_max, max: count_or_min_max)
  end

  def ascii_string(fmt, range, min: min) do
    ascii_string(fmt, range, min: min, max: :infinity)
  end

  def ascii_string(fmt, range, min: min, max: max) do
    fmap1(fmt, {&ascii_string_0/4, [range, min, max]})
  end

  @doc """
  If fmt results in `{:error, e}` this turns it into `{:error, label, e}`.
  """
  # label for error reports
  def label(fmt, label) do
    fn lst ->
      case invoke(fmt, lst) do
        {:error, e} -> {:error, {label, e}}
        ok -> ok
      end
    end
    |> prim
  end

  # def line(to_wrap), do: nil

  # def unmap() ?
  # def unreduce() expand?

  def optional(fmt \\ empty(), option) do
    concat(fmt, choice([option, empty()]))
  end

  # def repeat

  # def times(to_repeat, count_or_min_max), do: nil

  defp const_0(result, binary) do
    result <> binary
  end

  # equiv to ignore(string(empty, s)) in nimble; i.e. you can only ignore constants.
  @doc """
  Does not consume any values and appends the given binary to the result of the given formatter.
  """
  def const(fmt \\ empty(), binary)

  def const(fmt, binary) do
    map(fmt, {&const_0/2, [binary]})
  end

  defp untag_0(result, to_tag, tag) do
    case result do
      {^tag, v} -> invoke(to_tag, v)
      _ -> {:error, {:expected_tag, tag, result}}
    end
  end

  @spec untag(t, t, term) :: t
  @spec untag(t, term) :: t
  @doc """
  Takes `{tag, v}` from the value list, formats `v` with `to_tag`.
  """
  def untag(fmt \\ empty(), to_tag, tag)

  def untag(fmt, to_tag, tag) do
    fmap1(fmt, {&untag_0/3, [to_tag, tag]})
  end

  # @doc """
  # """
  # def wrap_and_untag(to_tag, tag) do
  #   fn lst ->
  #     case to_tag.(lst) do
  #       {^tag, lst} -> {:ok}
  #     end
  #   end
  # end

  # def unwrap(to_unwrap) when is_format(to_unwrap) do
  #   fn
  #     v ->
  #       case to_unwrap.(v) do
  #         [v] -> fmt.(v)
  #       end
  #     [lst] ->
  #       to_unwrap.(lst)
  #   end
  # end

  @doc """
  Defines a formatter with the given name and the given
  format. A formatter is a function that takes a list of values and returns `{:ok,
  binary}` or an error. Not that the format must consume the full input.
  """
  defmacro defformatter(name, fmt) do
    quote do
      def unquote(name)(input) do
        Active.Formatter.invoke(unquote(fmt), input)
      end
    end
  end
end
