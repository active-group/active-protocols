defmodule Coding.Test do
  use ExUnit.Case

  import Active.Coding
  alias Active.Coding.CharRange

  defcoding(:test_enc, :test_dec, non_neg_integer(2))

  test "defcoding" do
    test_v_in = 12
    {:ok, bin} = test_enc(test_v_in)
    {:ok, test_v_out, ""} = test_dec(bin)
    assert test_v_in == test_v_out

    assert :eof = test_dec("1")
  end

  def good_example_1(), do: {non_neg_integer(3), "123", 123}
  def good_example_2(), do: {byte_string(?a..?z, 3), "abc", "abc"}

  defmodule T do
    defstruct [:a, :b]
  end

  def roundtrip(coding, binary, value) do
    case encode(coding, value) do
      {:ok, binary2} ->
        if binary != binary2 do
          {:error, {:not_equal, binary, binary2}}
        else
          case decode(coding, binary) do
            {:ok, v, ""} -> if v == value, do: :ok, else: {:not_equal, v, value}
            {:ok, _v, r} -> {:error, {:not_fully_parsed, r}}
            :eof -> :eof
            {:error, reason} -> {:error, reason}
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  test "struct" do
    assert roundtrip(
             structure(T, a: non_neg_integer(2), b: non_neg_integer(3)),
             "12345",
             %T{a: 12, b: 345}
           ) == :ok
  end

  test "const" do
    {c, b, v} = good_example_1()
    assert roundtrip(prepend_const(c, "A"), "A" <> b, v) == :ok
    assert roundtrip(append_const(c, "A"), b <> "A", v) == :ok
  end

  test "tagged" do
    {c, b, v} = good_example_1()
    assert roundtrip(tagged(c, :foo), b, {:foo, v}) == :ok
  end

  test "list" do
    {c1, b1, v1} = good_example_1()
    {c2, b2, v2} = good_example_2()
    assert roundtrip(list([c1, c2]), b1 <> b2, [v1, v2]) == :ok
  end

  test "optional" do
    {c1, b1, v1} = good_example_1()
    assert roundtrip(optional(c1), b1, v1) == :ok
    assert roundtrip(optional(c1), "", nil) == :ok
  end

  test "encoding" do
    # Would like to test with :windows_1252 too, but don't know how to configure Codepagex just for the tests.
    enc = :iso_8859_1
    c = char_encoding(byte_string(CharRange.any(), 1), enc)
    v = "ä"
    b = <<228>>
    assert roundtrip(c, b, v) == :ok
  end
end
