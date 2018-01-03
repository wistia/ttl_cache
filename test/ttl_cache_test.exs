defmodule TTLCacheTest do
  use ExUnit.Case
  doctest TTLCache
  alias TTLCache.Server

  describe "TTLCache.Server.put/1" do
    test "puts the item to the server under the given key" do
      {:ok, pid} = Server.start_link(ttl: 1000)
      :ok = Server.put(pid, :hello, :world)
      assert Server.get(pid, :hello) == :world
    end

    test "can overwrite values" do
      {:ok, pid} = Server.start_link(ttl: 1000)
      :ok = Server.put(pid, :hello, :world)
      :ok = Server.put(pid, :hello, :everyone)
      assert Server.get(pid, :hello) == :everyone
    end

    test "expires after the ttl" do
      ttl = 500
      {:ok, pid} = Server.start_link(ttl: ttl)
      :ok = Server.put(pid, :hello, :world)
      :timer.sleep(1000)
      assert Server.get(pid, :hello) == nil
    end
  end

  describe "on_expire" do
    test "yields the value that is being expired" do
      myself = self()
      callback = fn value -> send(myself, value) end
      {:ok, pid} = Server.start_link(ttl: 500, on_expire: callback)
      :ok = Server.put(pid, :hello, :world)
      assert_receive {:hello, :world}, 1000
    end
  end

  describe "entries/1" do
    test "returns a map of the entries" do
      {:ok, pid} = Server.start_link(ttl: 1000)
      :ok = Server.put(pid, :hello, :world)
      :ok = Server.put(pid, :elixir, :is_cool)
      assert Server.entries(pid) == %{hello: :world, elixir: :is_cool}
    end
  end

  describe "keys/1" do
    test "returns all the keys" do
      {:ok, pid} = TTLCache.Server.start_link(ttl: 1000)
      :ok = TTLCache.Server.put(pid, :hello, :world)
      :ok = TTLCache.Server.put(pid, :elixir, :is_cool)
      keys = TTLCache.Server.keys(pid)
      assert :hello in keys
      assert :elixir in keys
    end
  end

  describe "values/1" do
    test "returns all the values" do
      {:ok, pid} = TTLCache.Server.start_link(ttl: 1000)
      :ok = TTLCache.Server.put(pid, :hello, :world)
      :ok = TTLCache.Server.put(pid, :elixir, :is_cool)
      values = TTLCache.Server.values(pid)
      assert :world in values
      assert :is_cool in values
    end
  end

  describe "delete/1" do
    test "deletes the entry" do
      {:ok, pid} = Server.start_link(ttl: 1000)
      :ok = Server.put(pid, :hello, :world)
      :ok = Server.delete(pid, :hello)
      assert Server.get(pid, :hello) == nil
    end

    test "doesn't call the expire callback" do
      parent = self()
      {:ok, pid} = Server.start_link(ttl: 1000, on_expire: fn _ -> send(parent, :yo) end)
      :ok = Server.put(pid, :hello, :world)
      :ok = Server.delete(pid, :hello)
      refute_received :yo, 1_000
    end
  end

  describe "init/1" do
    test "raises if invalid refresh_strategy" do
      assert_raise ArgumentError, fn ->
        Server.init(%{refresh_strategy: :bad_strat})
      end
    end
  end

  describe "never refresh strategy" do
    test "doesn't refresh on get()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :never)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :world == Server.get(pid, :hello)
      Process.sleep(250)
      assert nil == Server.get(pid, :hello)
    end

    test "doesn't refresh on entries()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :never)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert %{hello: :world} == Server.entries(pid)
      Process.sleep(250)
      assert nil == Server.get(pid, :hello)
    end

    test "doesn't refresh on get_and_update()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :never)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :world == Server.get_and_update(pid, :hello, &{&1, :mom})
      Process.sleep(250)
      assert nil == Server.get(pid, :hello)
    end

    test "doesn't refresh on put()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :never)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :ok == Server.put(pid, :hello, :mom)
      Process.sleep(250)
      assert nil == Server.get(pid, :hello)
    end

    test "doesn't refresh on update()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :never)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :ok == Server.update(pid, :hello, fn _ -> :mom end)
      Process.sleep(250)
      assert nil == Server.get(pid, :hello)
    end
  end

  describe "on_write refresh strategy" do
    test "doesn't refresh on get()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :world == Server.get(pid, :hello)
      Process.sleep(250)
      assert nil == Server.get(pid, :hello)
    end

    test "doesn't refresh on entries()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert %{hello: :world} == Server.entries(pid)
      Process.sleep(250)
      assert nil == Server.get(pid, :hello)
    end

    test "refreshes on get_and_update()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :world == Server.get_and_update(pid, :hello, &{&1, :mom})
      Process.sleep(250)
      assert :mom == Server.get(pid, :hello)
    end

    test "refreshes on get_and_update() even if the value doesn't change" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :world == Server.get_and_update(pid, :hello, &{&1, &1})
      Process.sleep(250)
      assert :world == Server.get(pid, :hello)
    end

    test "refreshes on put()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :ok == Server.put(pid, :hello, :mom)
      Process.sleep(250)
      assert :mom == Server.get(pid, :hello)
    end

    test "refreshes on put() even if the value doesn't change" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :ok == Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :world == Server.get(pid, :hello)
    end

    test "refreshes on update()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :ok == Server.update(pid, :hello, fn _ -> :mom end)
      Process.sleep(250)
      assert :mom == Server.get(pid, :hello)
    end

    test "refreshes on update() even if the value doesn't change" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :ok == Server.update(pid, :hello, & &1)
      Process.sleep(250)
      assert :world == Server.get(pid, :hello)
    end
  end

  describe "on_read refresh strategy" do
    test "refreshes on get()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :world == Server.get(pid, :hello)
      Process.sleep(250)
      assert :world == Server.get(pid, :hello)
    end

    test "doesn't refresh on entries()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert %{hello: :world} == Server.entries(pid)
      Process.sleep(250)
      assert nil == Server.get(pid, :hello)
    end

    test "doesn't refresh on get_and_update()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :world == Server.get_and_update(pid, :hello, &{&1, :mom})
      Process.sleep(250)
      assert nil == Server.get(pid, :hello)
    end

    test "doesn't refresh on put()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :ok == Server.put(pid, :hello, :mom)
      Process.sleep(250)
      assert nil == Server.get(pid, :hello)
    end

    test "doesn't refresh on update()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :ok == Server.update(pid, :hello, fn _ -> :mom end)
      Process.sleep(250)
      assert nil == Server.get(pid, :hello)
    end
  end

  describe "on_read_write refresh strategy" do
    test "refreshes on get()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :world == Server.get(pid, :hello)
      Process.sleep(250)
      assert :world == Server.get(pid, :hello)
    end

    test "doesn't refresh on entries()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert %{hello: :world} == Server.entries(pid)
      Process.sleep(250)
      assert nil == Server.get(pid, :hello)
    end

    test "refreshes on get_and_update()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :world == Server.get_and_update(pid, :hello, &{&1, :mom})
      Process.sleep(250)
      assert :mom == Server.get(pid, :hello)
    end

    test "refreshes on get_and_update() even if the value doesn't change" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :world == Server.get_and_update(pid, :hello, &{&1, &1})
      Process.sleep(250)
      assert :world == Server.get(pid, :hello)
    end

    test "refreshes on put()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :ok == Server.put(pid, :hello, :mom)
      Process.sleep(250)
      assert :mom == Server.get(pid, :hello)
    end

    test "refreshes on put() even if the value doesn't change" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :ok == Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :world == Server.get(pid, :hello)
    end

    test "refreshes on update()" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :ok == Server.update(pid, :hello, fn _ -> :mom end)
      Process.sleep(250)
      assert :mom == Server.get(pid, :hello)
    end

    test "refreshes on update() even if the value doesn't change" do
      {:ok, pid} = Server.start_link(ttl: 500, refresh_strategy: :on_read_write)
      :ok = Server.put(pid, :hello, :world)
      Process.sleep(250)
      assert :ok == Server.update(pid, :hello, & &1)
      Process.sleep(250)
      assert :world == Server.get(pid, :hello)
    end
  end
end
