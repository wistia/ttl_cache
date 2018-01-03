defmodule TTLCache.Server do
  require Logger
  use GenServer

  @global TTLCache.Server.Global
  @default_refresh_strategy :never
  @default_expiration_strategy :send_after
  @refresh_strategies [:never, :on_write]
  @expiration_strategies [:send_after]

  @doc """
  Creates a new server process.

  Accepts the following options:

    * `:ttl` - whenever a value is added to the cache via `put/3` it will expire based on
      this value (in milliseconds).

    * `:on_expire` - a callback that is triggered when an entry expires

    * `:refresh_strategy` - defines how to handle refreshing a key's ttl

    * `:expiration_strategy` - defines how to expire keys
  """
  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @doc """
  Adds `value` to the cache identified by `pid` under the key `key`. The value
  will expire based on the TTL provided in `TTLCache.Server.start_link/2`
  """
  def put(pid \\ @global, key, value) do
    GenServer.call(pid, {:put, key, value})
  end

  @doc """
  Returns the value associated with the key `key` for the cache identified by `pid`
  """
  def get(pid \\ @global, key) do
    {:ok, val} = GenServer.call(pid, {:get, key})
    val
  end

  @doc """
  Updates the value associated with the key `key` for the cache identified by `pid` with
  the given `fun`. `fun` will run on the server process and will block the server until
  it returns. The TTL will not be refreshed
  """
  def update(pid \\ @global, key, fun) do
    GenServer.call(pid, {:update, key, fun})
  end

  @doc """
  Modelled after Agent.get_and_update. Performs an atomic read-write operation
  """
  def get_and_update(pid \\ @global, key, fun) do
    {:ok, rv} = GenServer.call(pid, {:get_and_update, key, fun})
    rv
  end

  @doc """
  Remove the key from the given cache
  """
  def delete(pid \\ @global, key) do
    GenServer.call(pid, {:delete, key})
  end

  @doc """
  List all of the entries in the cache
  """
  def entries(pid \\ @global) do
    GenServer.call(pid, :entries)
  end

  @doc """
  List all of the keys in the cache
  """
  def keys(pid \\ @global) do
    entries(pid) |> Map.keys
  end

  @doc """
  List all of the values in the cache
  """
  def values(pid \\ @global) do
    entries(pid) |> Map.values
  end

  @doc """
  Stop the cache process
  """
  def stop(pid, reason \\ :normal) do
    GenServer.stop(pid, reason)
  end

  @doc false
  def init(args) do
    state = %{
      ttl: args[:ttl] || Application.fetch_env!(:ttl_cache, :ttl),
      on_expire: args[:on_expire],
      entries: %{},
      refresh_strategy: args[:refresh_strategy] || @default_refresh_strategy,
      expiration_strategy: args[:expiration_strategy] || @default_expiration_strategy,
      watermarks: %{}
    }
    validate_state!(state)
    {:ok, state}
  end

  @doc false
  def handle_call({:put, key, value}, _from, state) do
    state =
      state
      |> maybe_increment_watermark(key)
      |> maybe_start_expiration_clock(key)
      |> put_in([:entries, key], value)

    {:reply, :ok, state}
  end

  @doc false
  def handle_call({:get, key}, _from, state) do
    value = Map.get(state.entries, key)
    {:reply, {:ok, value}, state}
  end

  @doc false
  def handle_call({:get_and_update, key, fun}, _from, state) do
    value = Map.get(state.entries, key)
    {rv, transformed} = fun.(value)
    {:reply, {:ok, rv}, update_key_state(key, transformed, state)}
  end

  @doc false
  def handle_call({:update, key, fun}, _from, state) do
    value = Map.get(state.entries, key)
    transformed = fun.(value)
    {:reply, :ok, update_key_state(key, transformed, state)}
  end

  @doc false
  def handle_call(:entries, _from, state) do
    {:reply, state.entries, state}
  end

  @doc false
  def handle_call({:delete, key}, _from, state) do
    {:reply, :ok, delete_key(key, state)}
  end

  @doc false
  def handle_info({:expire, key, metadata}, state) do
    if expire?(state, key, metadata) do
      run_callback(state[:on_expire], {key, state[:entries][key]})
      {:noreply, delete_key(key, state)}
    else
      {:noreply, state}
    end
  end

  defp maybe_increment_watermark(state = %{refresh_strategy: :on_write}, key) do
    update_in(state[:watermarks][key], fn
      nil -> 0
      n -> n + 1
    end)
  end

  defp maybe_increment_watermark(state, _), do: state

  defp expire?(state = %{refresh_strategy: :on_write}, key, watermark) do
    Map.has_key?(state[:entries], key) && watermark == get_in(state, [:watermarks, key])
  end

  defp expire?(state, key, _) do
    Map.has_key?(state[:entries], key)
  end

  defp delete_key(key, state) do
    update_in(state[:entries], fn entries -> Map.delete(entries, key) end)
    |> update_in([:watermarks], fn watermarks -> Map.delete(watermarks, key) end)
  end

  defp update_key_state(key, :TTLCache_delete, state) do
    update_in(state[:entries], fn map -> Map.delete(map, key) end)
  end

  defp update_key_state(key, value, state) do
    maybe_increment_watermark(state, key)
    |> maybe_start_expiration_clock(key)
    |> put_in([:entries, key], value)
  end

  defp run_callback(nil, _), do: :ok
  defp run_callback(callback, arg), do: callback.(arg)

  defp maybe_start_expiration_clock(state = %{refresh_strategy: :on_write}, key) do
    current_watermark = state.watermarks[key]
    expire_in(key, state.ttl, current_watermark)
    state
  end

  defp maybe_start_expiration_clock(state, key) do
    if key in Map.keys(state.entries) do
      :ok
    else
      expire_in(key, state.ttl)
    end

    state
  end

  defp expire_in(key, ttl, metadata \\ nil) do
    Process.send_after(self(), {:expire, key, metadata}, ttl)
  end

  defp validate_state!(%{refresh_strategy: refresh_strategy, expiration_strategy: expiration_strategy }) do
    unless refresh_strategy in @refresh_strategies do
      raise ArgumentError, "Invalid refresh_strategy"
    end

    unless expiration_strategy in @expiration_strategies do
      raise ArgumentError, "Invalid expiration_strategy"
    end
  end
end
