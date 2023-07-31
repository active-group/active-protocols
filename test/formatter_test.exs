defmodule FormatterTest do
  use ExUnit.Case

  import Active.Formatter

  test "defformatter test" do
    defmodule Test do
      defformatter(:test1, non_neg_integer(2))
    end

    assert Test.test1(42) == {:ok, "42"}
  end

  def invalid_example(), do: {non_neg_integer(3), ["foo"]}
  def good_example_1(), do: {non_neg_integer(3), 123, "123"}
  def good_example_2(), do: {byte_string([?a..?z], 3), "abc", "abc"}

  test "integer formatting" do
    assert invoke(non_neg_integer(3), 123) == {:ok, "123"}
    assert invoke(non_neg_integer(3), 1) == {:ok, "001"}
    assert invoke(non_neg_integer(min: 1, max: 3), 1) == {:ok, "1"}
  end

  test "string formatting" do
    assert invoke(byte_string([?0..?9], 3), "123") == {:ok, "123"}

    assert invoke(byte_string([?0..?9], min: 1, max: 3), "123") == {:ok, "123"}
    assert invoke(byte_string([?0..?9], min: 1, max: 3), "1") == {:ok, "1"}

    assert invoke(byte_string([?0..?9], 3), "1") ==
             {:error, {:wrong_string_size, "1", 3, 3}}
  end

  test "choice" do
    {fmt1, v1, r1} = good_example_1()
    {fmt2, v2, r2} = good_example_2()

    fmt = choice([fmt1, fmt2])

    assert invoke(fmt, v1) == {:ok, r1}
    assert invoke(fmt, v2) == {:ok, r2}
  end

  test "list" do
    {fmt1, v1, r1} = good_example_1()
    {fmt2, v2, r2} = good_example_2()

    assert invoke(list([fmt1, fmt2]), [v1, v2]) == {:ok, r1 <> r2}
  end

  test "label" do
    {fmt, v} = invalid_example()
    {:error, e} = invoke(fmt, v)
    assert invoke(fmt |> label(:x), v) == {:error, {:x, e}}
  end

  test "const" do
    {fmt1, v1, r1} = good_example_1()
    assert invoke(prepend_const(fmt1, "A"), v1) == {:ok, "A" <> r1}
    assert invoke(append_const(fmt1, "A"), v1) == {:ok, r1 <> "A"}
  end

  test "untag" do
    {fmt1, v1, r1} = good_example_1()
    assert invoke(untag(fmt1, :foo), {:foo, v1}) == {:ok, r1}

    assert invoke(untag(fmt1, :foo), {:bar, v1}) ==
             {:error, {:expected_tagged_tuple, :foo, {:bar, v1}}}
  end

  test "unstruct" do
    {fmt1, v1, r1} = good_example_1()
    {fmt2, v2, r2} = good_example_2()
    assert invoke(unstruct(a: fmt1, b: fmt2), %{a: v1, b: v2}) == {:ok, r1 <> r2}
  end
end
