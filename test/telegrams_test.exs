defmodule TelegramsTest do
  use ExUnit.Case

  require ExampleTelegrams

  doctest Telegrams

  ############################################################

  test "parse unparse Moduled roundtrip works" do
    alias ExampleTelegrams.Telegram1
    alias ExampleTelegrams.Telegram2
    alias ExampleTelegrams.Telegram

    assert Telegram1.parse(<<>>) == {:need_more, 3}
    assert Telegram1.parse(<<1, 42, 43>>) == {:ok, %Telegram1{message: <<42, 43>>}}
    assert Telegram1.unparse(%Telegram1{message: <<42, 43>>}) == <<1, 42, 43>>
    assert Telegram1.parse(<<2>>) == {:error, :parse_failed}

    assert Telegram2.parse(<<>>) == {:need_more, 2}
    assert Telegram2.parse(<<2, 42>>) == {:ok, %Telegram2{counter: 42}}
    assert Telegram2.parse(<<1>>) == {:error, :parse_failed}

    v = %Telegram1{message: "xy"}
    assert Telegram.unparse(v) == <<1>> <> "xy"
    assert Telegram.parse(Telegram.unparse(v)) == {:ok, v}

    v2 = %Telegram2{counter: 42}
    assert Telegram.parse(Telegram.unparse(v2)) == {:ok, v2}
  end
end
