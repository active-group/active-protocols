defmodule Active.Formatter do
  # Fmt is private
  @doc false
  defmodule Fmt do
    defstruct [:f, :args]
  end

  # can't be @opaque, can it?
  @type t() :: %Fmt{}

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

  # @spec prim((term -> {:ok, binary} | {:error, term}), [term]) :: t()
  defp prim(f, args) do
    %Fmt{f: f, args: args}
  end

  ############################################################

  defp fmap_0(input, fmt, f, args) do
    b = invoke(fmt, input)
    apply(f, [b] ++ args)
  end

  # change result (ok/error) of fmt to ok/error
  def fmap(fmt, {f, args}) do
    prim(&fmap_0/4, [fmt, f, args])
  end

  defp map_0(result, f, args) do
    case result do
      {:ok, b} -> apply(f, [b] ++ args)
      err -> err
    end
  end

  # change successful output of fmt, to ok/error.
  def map(fmt, {f, args}) do
    fmap(fmt, {&map_0/3, [f, args]})
  end

  defp cofmap_0(value, fmt, f, args) do
    case apply(f, [value] ++ args) do
      {:ok, v} -> invoke(fmt, v)
      {:error, reason} -> {:error, reason}
    end
  end

  # change a value or fail before formatting to ok/error
  def cofmap(fmt, {f, args}) do
    prim(&cofmap_0/4, [fmt, f, args])
  end

  defp comap_0(input, f, args) do
    {:ok, apply(f, [input] ++ args)}
  end

  # change a value before formatting.
  def comap(fmt, {f, args}) do
    cofmap(fmt, {&comap_0/3, [f, args]})
  end

  # defp return_0(_input, v) do
  #   {:ok, v}
  # end

  # defp return(v) do
  #  prim(&return_0/2, [v])
  # end

  # def error(_fmt, e) do
  #   fn input -> {:error, e} end
  # end

  # def empty(), do: return(<<>>)

  ############################################################

  # defp concat_0(input, left, right) do
  #   case input do
  #     [input_l, input_r] ->
  #       case invoke(left, input_l) do
  #         {:ok, left_res} ->
  #           case invoke(right, input_r) do
  #             {:ok, right_res} ->
  #               {:ok, left_res <> right_res}

  #             err ->
  #               err
  #           end

  #         err ->
  #           err
  #       end

  #     _ ->
  #       {:error, {:list_of_two_expected, input}}
  #   end
  # end

  # def concat(left, right) when is_format(left) and is_format(right) do
  #   cond do
  #     left == empty() ->
  #       right

  #     right == empty() ->
  #       left

  #     true ->
  #       prim(&concat_0/3, [left, right])
  #   end
  # end

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

  def choice(choices) do
    # TODO when length(choices) >= 2
    case choices do
      [c1 | cr] -> prim(&choice_0/3, [c1, cr])
    end

    # TODO: change error into 'expected one of...'
    # |> fmap({&choice_error/2, [choices]})
  end

  defp non_neg_integer_0(v, min, max) do
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
  def non_neg_integer(digits_or_min_max)

  def non_neg_integer(digits_or_min_max) when is_integer(digits_or_min_max) do
    non_neg_integer(min: digits_or_min_max, max: digits_or_min_max)
  end

  def non_neg_integer(min: min) do
    non_neg_integer(min: min, max: :infinity)
  end

  def non_neg_integer(min: min, max: max) do
    prim(&non_neg_integer_0/3, [min, max])
  end

  defp byte_string_0(s, range, min, max) do
    if is_binary(s) do
      bad = Enum.any?(:binary.bin_to_list(s), fn c -> not Enum.member?(range, c) end)

      if bad do
        {:error, {:invalid_chars, range, s}}
      else
        case byte_size(s) do
          l when l >= min and (max == :infinity or l <= max) -> {:ok, s}
          _ -> {:error, {:wrong_string_size, s, min, max}}
        end
      end
    else
      {:error, {:string_expected, s}}
    end
  end

  defp to_enc(str, encoding) do
    case Codepagex.from_string(str, encoding, Codepagex.use_utf_replacement()) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason} -> {:error, {:not_encodable, encoding, str, reason}}
    end
  end

  def char_encoding(string_fmt, encoding) do
    cofmap(string_fmt, {&to_enc/2, [encoding]})
  end

  # TODO: same as in coding...
  @type range :: term

  @spec byte_string(
          term,
          pos_integer() | [{:min, non_neg_integer()} | {:max, pos_integer()}]
        ) :: t()
  def byte_string(range, count_or_min_max)

  def byte_string(range, count_or_min_max) when is_integer(count_or_min_max) do
    byte_string(range, min: count_or_min_max, max: count_or_min_max)
  end

  def byte_string(range, min: min) do
    byte_string(range, min: min, max: :infinity)
  end

  def byte_string(range, min: min, max: max) do
    prim(&byte_string_0/4, [MapSet.new(range), min, max])
  end

  defp label_0(result, label) do
    case result do
      {:error, e} -> {:error, {label, e}}
      ok -> ok
    end
  end

  @doc """
  If fmt results in `{:error, e}` this turns it into `{:error, label, e}`.
  """
  # label for error reports
  def label(fmt, label) do
    fmap(fmt, {&label_0/2, [label]})
  end

  # def line(to_wrap), do: nil

  # def unmap() ?
  # def unreduce() expand?

  defp optional_0(input, option) do
    case input do
      nil -> {:ok, <<>>}
      _ -> invoke(option, input)
    end
  end

  @doc """
  Use format 'option' only if input is not nil. Return <<>> if it is nil.
  """
  def optional(option) do
    prim(&optional_0/2, [option])
  end

  # def repeat

  # def times(to_repeat, count_or_min_max), do: nil

  defp append_const_0(result, binary) do
    {:ok, result <> binary}
  end

  @doc """
  Append the given binary after the output of the given format.
  """
  def append_const(fmt, binary) do
    map(fmt, {&append_const_0/2, [binary]})
  end

  defp prepend_const_0(result, binary) do
    {:ok, binary <> result}
  end

  def prepend_const(fmt, binary) do
    map(fmt, {&prepend_const_0/2, [binary]})
  end

  defp untag_0(input, tag) do
    case input do
      {^tag, v} -> {:ok, v}
      _ -> {:error, {:expected_tagged_tuple, tag, input}}
    end
  end

  @spec untag(t, term) :: t
  @doc """
  Takes `{tag, v}` from the value list, formats `v` with `to_tag`.
  """
  def untag(to_tag, tag)

  def untag(to_tag, tag) do
    cofmap(to_tag, {&untag_0/2, [tag]})
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

  defp unstruct_0(input, struct_module, fields_formats) do
    if is_struct(input, struct_module) do
      {fields, formats} = Enum.unzip(fields_formats)

      case Enum.reduce(fields, true, fn f, acc -> acc && Map.has_key?(input, f) end) do
        true ->
          values = Enum.map(fields, fn f -> Map.fetch!(input, f) end)
          invoke(list(formats), values)

        false ->
          {:error, {:struct_fields_missing, fields, input}}
      end
    else
      {:error, {:not_struct, struct_module, input}}
    end
  end

  @spec unstruct(atom, [{atom, t()}]) :: t
  def unstruct(struct_module, fields_formats) do
    prim(&unstruct_0/3, [struct_module, fields_formats])
  end

  # defp unwrap_0(input, on_element) do
  #   case input do
  #     [v] -> invoke(on_element, v)
  #     _ -> {:error, {:expected_one_element_list, input}}
  #   end
  # end

  # @doc """
  # Expects the input to be a one element list, and then applying the given formatter on the element.
  # """
  # def unwrap(fmt \\ empty(), on_element) do
  #   concat(fmt, prim(&unwrap_0/2, [on_element]))
  # end

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
