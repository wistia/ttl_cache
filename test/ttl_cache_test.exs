defmodule TTLCacheTest do
  use ExUnit.Case
  doctest TTLCache

  describe "TTLCache.Server.put/1" do
    test "puts the item to the server under the given key" do
      {:ok, pid} = TTLCache.Server.start_link(ttl: 1000)
      :ok = TTLCache.Server.put(pid, :hello, :world)
      assert TTLCache.Server.get(pid, :hello) == :world
    end

    test "can overwrite values" do
      {:ok, pid} = TTLCache.Server.start_link(ttl: 1000)
      :ok = TTLCache.Server.put(pid, :hello, :world)
      :ok = TTLCache.Server.put(pid, :hello, :everyone)
      assert TTLCache.Server.get(pid, :hello) == :everyone
    end

    test "expires after the ttl" do
      ttl = 500
      {:ok, pid} = TTLCache.Server.start_link(ttl: ttl)
      :ok = TTLCache.Server.put(pid, :hello, :world)
      :timer.sleep(1000)
      assert TTLCache.Server.get(pid, :hello) == nil
    end

    test "with refresh_strategy = :on_write, refreshes the TTL" do
      ttl = 500
      {:ok, pid} = TTLCache.Server.start_link(ttl: ttl, refresh_strategy: :on_write)
      :ok = TTLCache.Server.put(pid, :hello, :world)

      # Sleep for half of the TTL then update (elapsed = ttl / 2)
      :timer.sleep(round(ttl / 2))
      :ok = TTLCache.Server.put(pid, :hello, :mom)

      # Wake up after the original expire would have happened (elapsed = (7/6) * ttl)
      :timer.sleep(round(ttl * 2 / 3))
      assert TTLCache.Server.get(pid, :hello) == :mom

      # Wake up after the updated expire should have happened (elapsed > 2 * ttl)
      :timer.sleep(ttl)
      assert TTLCache.Server.get(pid, :hello) == nil
    end
  end

  describe "on_expire" do
    test "yields the value that is being expired" do
      myself = self()
      callback = fn value -> send(myself, value) end
      {:ok, pid} = TTLCache.Server.start_link(ttl: 500, on_expire: callback)
      :ok = TTLCache.Server.put(pid, :hello, :world)
      assert_receive {:hello, :world}, 1000
    end
  end

  describe "TTLCache.Server.entries/1" do
    test "returns a map of the entries" do
      {:ok, pid} = TTLCache.Server.start_link(ttl: 1000)
      :ok = TTLCache.Server.put(pid, :hello, :world)
      :ok = TTLCache.Server.put(pid, :elixir, :is_cool)
      assert TTLCache.Server.entries(pid) == %{hello: :world, elixir: :is_cool}
    end
  end

  describe "TTLCache.Server.delete/1" do
    test "deletes the entry" do
      {:ok, pid} = TTLCache.Server.start_link(ttl: 1000)
      :ok = TTLCache.Server.put(pid, :hello, :world)
      :ok = TTLCache.Server.delete(pid, :hello)
      assert TTLCache.Server.get(pid, :hello) == nil
    end

    test "doesn't call the expire callback" do
      parent = self()
      {:ok, pid} = TTLCache.Server.start_link(ttl: 1000, on_expire: fn _ -> send(parent, :yo) end)
      :ok = TTLCache.Server.put(pid, :hello, :world)
      :ok = TTLCache.Server.delete(pid, :hello)
      refute_received :yo, 1_000
    end
  end

  describe "TTLCache.Server.init/1" do
    test "raises if invalid refresh_strategy" do
      assert_raise ArgumentError, fn ->
        TTLCache.Server.init(%{refresh_strategy: :bad_strat})
      end
    end
  end
end
