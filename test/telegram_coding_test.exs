defmodule Telegram.Coding.Test do
  use ExUnit.Case

  import Active.Coding
  import Active.Telegram.Coding

  defmodule TestTelegram do
    use Active.Telegram.Coding, coding: non_neg_integer(2)
  end

  test "as telegram" do
    {:ok, binary} = TestTelegram.encode(12)
    {:ok, 12, <<>>} = TestTelegram.decode(binary)
  end
end
