defmodule TelegramsTest do
  use ExUnit.Case

  require ExampleTelegrams

  ############################################################

  test "encode decode roundtrip works" do
    alias ExampleTelegrams.Telegram1
    alias ExampleTelegrams.Telegram2

    assert Telegram1.decode(<<>>) == {:error, :eof}
    assert Telegram1.decode(<<1, 42, 43>>) == {:ok, %Telegram1{message: <<42, 43>>}, ""}
    assert Telegram1.encode(%Telegram1{message: <<42, 43>>}) == {:ok, <<1, 42, 43>>}
    assert Telegram1.decode(<<2>>) == {:error, :decode_failed}

    assert Telegram2.decode(<<>>) == {:error, :eof}
    assert Telegram2.decode(<<2, 42>>) == {:ok, %Telegram2{counter: 42}, ""}
    assert Telegram2.decode(<<2, 42, 55>>) == {:ok, %Telegram2{counter: 42}, <<55>>}
    assert Telegram2.decode(<<1>>) == {:error, :decode_failed}

    v = %Telegram1{message: "xy"}
    assert Telegram1.encode(v) == {:ok, <<1>> <> "xy"}
    {:ok, bytes} = Telegram1.encode(v)
    assert Telegram1.decode(bytes) == {:ok, v, ""}

    v2 = %Telegram2{counter: 42}
    {:ok, bytes2} = Telegram2.encode(v2)
    assert Telegram2.decode(bytes2) == {:ok, v2, ""}
  end
end
