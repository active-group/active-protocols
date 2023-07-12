defmodule TelegramsTest do
  use ExUnit.Case

  require ExampleTelegrams

  doctest Telegrams

  ############################################################

  test "encode decode roundtrip works" do
    alias ExampleTelegrams.Telegram1
    alias ExampleTelegrams.Telegram2
    alias ExampleTelegrams.Telegram

    assert Telegram1.decode(<<>>) == {:need_more, 3}
    assert Telegram1.decode(<<1, 42, 43>>) == {:ok, %Telegram1{message: <<42, 43>>}}
    assert Telegram1.encode(%Telegram1{message: <<42, 43>>}) == <<1, 42, 43>>
    assert Telegram1.decode(<<2>>) == {:error, :decode_failed}

    assert Telegram2.decode(<<>>) == {:need_more, 2}
    assert Telegram2.decode(<<2, 42>>) == {:ok, %Telegram2{counter: 42}}
    assert Telegram2.decode(<<1>>) == {:error, :decode_failed}

    v = %Telegram1{message: "xy"}
    assert Telegram.encode(v) == <<1>> <> "xy"
    assert Telegram.decode(Telegram.encode(v)) == {:ok, v}

    v2 = %Telegram2{counter: 42}
    assert Telegram.decode(Telegram.encode(v2)) == {:ok, v2}
  end
end
