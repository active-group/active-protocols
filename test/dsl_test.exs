defmodule Coding.DSLTest do
  use ExUnit.Case

  import Active.Coding.DSL

  defcoding(:test_enc, :test_dec, non_neg_integer(2))

  test "defcoding" do
    test_v_in = [12]
    {:ok, bin, []} = test_enc(test_v_in)
    {:ok, test_v_out, "", _ctx, _line, _column} = test_dec(bin)
    assert test_v_in == test_v_out

    assert :eof = test_dec("1")
  end

  defmodule TestTelegram do
    use Active.Coding.Telegram, coding: non_neg_integer(2)
  end

  test "as telegram" do
    {:ok, binary} = TestTelegram.encode(12)
    {:ok, 12, ""} = TestTelegram.decode(binary)
  end
end
