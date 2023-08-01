defmodule ParserTest do
  use ExUnit.Case

  import Active.Parser

  def invoke_full(p, input) do
    case invoke(p, input) do
      {:ok, result, ""} -> {:ok, result}
      {:ok, _result, rest} -> {:error, {:extra_input, rest}}
      err -> err
    end
  end

  test "defparser test" do
    defmodule Test do
      defparser(:test1, non_neg_integer(2))
    end

    assert Test.test1("42") == {:ok, 42, ""}
  end

  def invalid_example(), do: {non_neg_integer(3), "foo"}
  def good_example_1(), do: {non_neg_integer(3), "123", 123}
  def good_example_2(), do: {byte_string(?a..?z, 3), "abc", "abc"}

  test "integer parsing" do
    assert invoke_full(non_neg_integer(3), "123") == {:ok, 123}
    assert invoke_full(non_neg_integer(3), "001") == {:ok, 1}
    assert invoke_full(non_neg_integer(min: 1, max: 3), "1") == {:ok, 1}
  end

  test "string parsing" do
    assert invoke_full(byte_string(?0..?9, 3), "123") == {:ok, "123"}

    assert invoke_full(byte_string(?0..?9, min: 1, max: 3), "123") == {:ok, "123"}
    assert invoke_full(byte_string(?0..?9, min: 1, max: 3), "1") == {:ok, "1"}

    assert invoke_full(byte_string(?0..?9, 3), "1") == :eof
  end

  test "delimited string parsing" do
    p = append_const(byte_string(?0..?9, min: 1, max: 3), "X")

    assert invoke_full(p, "X") == {:error, {:not_in_range, ?0..?9, "X"}}
    assert invoke_full(p, "1X") == {:ok, "1"}
    assert invoke_full(p, "12X") == {:ok, "12"}
    assert invoke_full(p, "123X") == {:ok, "123"}
    assert invoke_full(p, "1234X") == {:error, {:expected, "X", "4"}}
  end

  test "choice" do
    {p1, v1, r1} = good_example_1()
    {p2, v2, r2} = good_example_2()

    p = choice([p1, p2])
    assert invoke_full(p, v1) == {:ok, r1}
    assert invoke_full(p, v2) == {:ok, r2}
  end

  test "wrap" do
    {p1, v1, r1} = good_example_1()
    {p2, v2, r2} = good_example_2()
    assert invoke_full(wrap(p1), v1) == {:ok, [r1]}
    assert invoke_full(wrap(p2), v2) == {:ok, [r2]}
  end

  test "list" do
    {p1, v1, r1} = good_example_1()
    {p2, v2, r2} = good_example_2()

    assert invoke_full(list([p1, p2]), v1 <> v2) == {:ok, [r1, r2]}
  end

  test "label" do
    {p, v} = invalid_example()
    {:error, e} = invoke_full(p, v)
    assert invoke_full(p |> label(:x), v) == {:error, {:x, e}}
  end

  test "const" do
    {p1, v1, r1} = good_example_1()
    assert invoke_full(prepend_const(p1, "A"), "A" <> v1) == {:ok, r1}
    assert invoke_full(append_const(p1, "A"), v1 <> "A") == {:ok, r1}
  end

  test "tag" do
    {p1, v1, r1} = good_example_1()
    assert invoke_full(p1 |> tag(:foo), v1) == {:ok, {:foo, r1}}
  end

  defmodule T do
    defstruct [:a, :b]
  end

  test "struct" do
    {p1, v1, r1} = good_example_1()
    {p2, v2, r2} = good_example_2()
    assert invoke_full(structure(T, a: p1, b: p2), v1 <> v2) == {:ok, %T{a: r1, b: r2}}
  end
end
