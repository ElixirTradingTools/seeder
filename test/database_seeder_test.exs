defmodule SeederTest do
  use ExUnit.Case
  doctest Seeder

  test "greets the world" do
    assert Seeder.hello() == :world
  end
end
