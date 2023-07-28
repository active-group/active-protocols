defmodule FormatterTest do
  use ExUnit.Case

  import Active.Formatter

  def invoke_full(fmt, input) do
    case invoke(fmt, input) do
      {:ok, result, []} -> {:ok, result}
      {:ok, _result, rest} -> {:error, {:extra_input, rest}}
      err -> err
    end
  end

  test "defformatter test" do
    defmodule Test do
      defformatter(:test1, non_neg_integer(2))
    end

    assert Test.test1([42]) == {:ok, "42", []}
  end

  def invalid_example(), do: {non_neg_integer(3), ["foo"]}
  def good_example_1(), do: {non_neg_integer(3), [123], "123"}
  def good_example_2(), do: {byte_string([?0..?9], 3), ["456"], "456"}

  test "integer formatting" do
    assert invoke_full(non_neg_integer(3), [123]) == {:ok, "123"}
    assert invoke_full(non_neg_integer(3), [1]) == {:ok, "001"}
    assert invoke_full(non_neg_integer(min: 1, max: 3), [1]) == {:ok, "1"}
  end

  test "string formatting" do
    assert invoke_full(byte_string([?0..?9], 3), ["123"]) == {:ok, "123"}

    assert invoke_full(byte_string([?0..?9], min: 1, max: 3), ["123"]) == {:ok, "123"}
    assert invoke_full(byte_string([?0..?9], min: 1, max: 3), ["1"]) == {:ok, "1"}

    assert invoke_full(byte_string([?0..?9], 3), ["1"]) ==
             {:error, {:wrong_string_size, "1", 3, 3}}
  end

  test "choice" do
    {fmt1, v1, r1} = good_example_1()
    {fmt2, v2, r2} = good_example_2()

    fmt = choice([fmt1, fmt2])
    assert invoke_full(fmt, v1) == {:ok, r1}
    assert invoke_full(fmt, v2) == {:ok, r2}
  end

  test "concat" do
    {fmt1, v1, r1} = good_example_1()
    {fmt2, v2, r2} = good_example_2()

    assert invoke_full(concat(fmt1, fmt2), v1 ++ v2) == {:ok, r1 <> r2}
  end

  test "label" do
    {fmt, v} = invalid_example()
    {:error, e} = invoke_full(fmt, v)
    assert invoke_full(fmt |> label(:x), v) == {:error, {:x, e}}
  end

  test "const" do
    assert invoke_full(const("A"), []) == {:ok, "A"}
  end

  test "untag" do
    {fmt1, v1, r1} = good_example_1()
    assert invoke_full(fmt1 |> untag(:foo), [{:foo, v1}]) == {:ok, r1}

    assert invoke_full(fmt1 |> untag(:foo), [{:bar, []}]) ==
             {:error, {:expected_tag, :foo, {:bar, []}}}
  end
end
