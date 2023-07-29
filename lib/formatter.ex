defmodule Active.Formatter do
  # Fmt is private
  @doc false
  defmodule Fmt do
    defstruct [:f, :args]
  end

  @opaque t() :: %Fmt{}

  defmacro is_format(v) do
    quote do
      is_struct(unquote(v), Fmt)
    end
  end

  # only for macro and tests.
  @doc false
  def invoke(fmt, input) do
    apply(fmt.f, [input] ++ fmt.args)
  end

  @spec prim((term -> {:ok, binary} | {:error, term}), [term]) :: t()
  defp prim(f, args) do
    %Fmt{f: f, args: args}
  end

  ############################################################

  # TODO: need comap, cofmap instead of all the prims.

  defp map_0(input, fmt, {f, args}) do
    case invoke(fmt, input) do
      {:ok, b} -> {:ok, apply(f, [b] ++ args)}
      err -> err
    end
  end

  def map(fmt, {f, args}) do
    prim(&map_0/3, [fmt, {f, args}])
  end

  defp fmap_0(input, fmt, {f, args}) do
    case invoke(fmt, input) do
      {:ok, b} -> apply(f, [b] ++ args)
      err -> err
    end
  end

  def fmap(fmt, {f, args}) do
    prim(&fmap_0/3, [fmt, {f, args}])
  end

  defp return_0(_input, v) do
    {:ok, v}
  end

  defp return(v) do
    prim(&return_0/2, [v])
  end

  # def error(_fmt, e) do
  #   fn input -> {:error, e} end
  # end

  def empty(), do: return(<<>>)

  ############################################################

  defp concat_0(input, left, right) do
    case input do
      [input_l, input_r] ->
        case invoke(left, input_l) do
          {:ok, left_res} ->
            case invoke(right, input_r) do
              {:ok, right_res} ->
                {:ok, left_res <> right_res}

              err ->
                err
            end

          err ->
            err
        end

      _ ->
        {:error, {:list_of_two_expected, input}}
    end
  end

  def concat(left, right) when is_format(left) and is_format(right) do
    cond do
      left == empty() ->
        right

      right == empty() ->
        left

      true ->
        prim(&concat_0/3, [left, right])
    end
  end

  defp choice_0(input, c, cr) do
    case cr do
      [] ->
        invoke(c, input)

      [c_ | cr_] ->
        case invoke(c, input) do
          {:ok, result} ->
            {:ok, result}

          _err ->
            choice_0(input, c_, cr_)
        end
    end
  end

  def choice(fmt \\ empty(), choices) do
    # TODO when length(choices) >= 2
    case choices do
      [c1 | cr] -> concat(fmt, prim(&choice_0/3, [c1, cr]))
    end

    # TODO: change error into 'expected one of...'
    # |> fmap({&choice_error/2, [choices]})
  end

  defp non_neg_integer_0(v, min, max) do
    # TODO: check if v is non-neg, add padding (option if '0' or ' '? front or back?), etc.
    cond do
      !is_integer(v) ->
        {:error, {:integer_expected, v}}

      v < 0 ->
        {:error, {:non_neg_integer_expected, v}}

      true ->
        s = Integer.to_string(v)
        l = byte_size(s)

        cond do
          l <= min -> {:ok, String.pad_leading(s, min, "0")}
          max == :infinity || l == max -> {:ok, s}
          true -> {:error, {:integer_too_large, [min: min, max: max], v}}
        end
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
    concat(fmt, prim(&non_neg_integer_0/3, [min, max]))
  end

  defp byte_string_0(s, range, min, max) do
    # TODO: check if all bytes are in the range, maybe pad with ' ' if too short? (option if front or back?)
    if is_binary(s) do
      case byte_size(s) do
        l when l >= min and (max == :infinity or l <= max) -> {:ok, s}
        _ -> {:error, {:wrong_string_size, s, min, max}}
      end
    else
      {:error, {:string_expected, s}}
    end
  end

  # TODO: add string()? using erlang:iconv or Codepagex?

  @spec byte_string(
          t(),
          [char],
          pos_integer() | [{:min, non_neg_integer()} | {:max, pos_integer()}]
        ) :: t()
  def byte_string(fmt \\ empty(), range, count_or_min_max)

  def byte_string(fmt, range, count_or_min_max) when is_integer(count_or_min_max) do
    byte_string(fmt, min: count_or_min_max, max: count_or_min_max)
  end

  def byte_string(fmt, range, min: min) do
    byte_string(fmt, range, min: min, max: :infinity)
  end

  def byte_string(fmt, range, min: min, max: max) do
    concat(fmt, prim(&byte_string_0/4, [range, min, max]))
  end

  defp label_0(input, fmt, label) do
    case invoke(fmt, input) do
      {:error, e} -> {:error, {label, e}}
      ok -> ok
    end
  end

  @doc """
  If fmt results in `{:error, e}` this turns it into `{:error, label, e}`.
  """
  # label for error reports
  def label(fmt, label) do
    prim(&label_0/3, [fmt, label])
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

  defp untag_0(input, to_tag, tag) do
    case input do
      {^tag, v} -> invoke(to_tag, v)
      _ -> {:error, {:expected_tagged_tuple, tag, input}}
    end
  end

  @spec untag(t, t, term) :: t
  @spec untag(t, term) :: t
  @doc """
  Takes `{tag, v}` from the value list, formats `v` with `to_tag`.
  """
  def untag(fmt \\ empty(), to_tag, tag)

  def untag(fmt, to_tag, tag) do
    concat(fmt, prim(&untag_0/3, [to_tag, tag]))
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

  def list_0(input, formatters) do
    Enum.reduce_while(
      Enum.zip(input, formatters),
      {:ok, <<>>},
      fn {input, fmt}, acc ->
        {:ok, bs} = acc

        case invoke(fmt, input) do
          {:ok, bytes} -> {:cont, {:ok, bs <> bytes}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end
    )
  end

  @doc """
  Format a list of values, with a corresponding list of formats.
  """
  def list(formatters) do
    prim(&list_0/2, [formatters])
  end

  defp unstruct_0(input, fields_formats) do
    {fields, formats} = Enum.unzip(fields_formats)
    values = Enum.map(fields, fn f -> Map.get(input, f) end)
    invoke(list(formats), values)
  end

  @spec unstruct(t, %{atom => t}) :: t
  def unstruct(fmt \\ empty(), fields_formats) do
    concat(fmt, prim(&unstruct_0/2, [fields_formats]))
  end

  defp unwrap_0(input, on_element) do
    case input do
      [v] -> invoke(on_element, v)
      _ -> {:error, {:expected_one_element_list, input}}
    end
  end

  @doc """
  Expects the input to be a one element list, and then applying the given formatter on the element.
  """
  def unwrap(fmt \\ empty(), on_element) do
    concat(fmt, prim(&unwrap_0/2, [on_element]))
  end

  @doc """
  Defines a formatter with the given name and the given
  format. A formatter is a function that takes a list of values and returns `{:ok,
  binary, rest_input}` or an error.
  """
  defmacro defformatter(name, fmt) do
    quote do
      def unquote(name)(input) do
        Active.Formatter.invoke(unquote(fmt), input)
      end
    end
  end
end
