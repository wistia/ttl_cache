defmodule TTLCache.Server do
  require Logger
  use GenServer

  @global TTLCache.Server.Global
  @default_refresh_strategy :never
  @default_expiration_strategy TTLCache.Expiration.SendAfter
  @refresh_strategies [:never, :on_write, :on_read, :on_read_write]
  @expiration_strategies [TTLCache.Expiration.SendAfter]

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
  it returns. The TTL will not be refreshed. The special value of :TTLCache_delete can be
  returned by `fun` to atomically instead delete the value
  """
  def update(pid \\ @global, key, fun) do
    GenServer.call(pid, {:update, key, fun})
  end

  @doc """
  Modelled after Agent.get_and_update. Performs an atomic read-write operation. The special
  value of :TTLCache_delete can be returned by `fun` to atomically instead delete the value
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
  Returns whether or not the key is in the cache
  """
  def has_key?(pid \\ @global, key) do
    entries(pid) |> Map.has_key?(key)
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
    refresh_strategy = args[:refresh_strategy] || @default_refresh_strategy
    expiration_strategy = args[:expiration_strategy] || @default_expiration_strategy

    unless refresh_strategy in @refresh_strategies do
      raise ArgumentError, "Invalid refresh_strategy"
    end

    unless expiration_strategy in @expiration_strategies do
      raise ArgumentError, "Invalid expiration_strategy"
    end

    state = %{
      ttl: args[:ttl] || Application.fetch_env!(:ttl_cache, :ttl),
      on_expire: args[:on_expire],
      on_read: &expiration_strategy.on_read/2,
      on_write: &expiration_strategy.on_write/2,
      on_delete: &expiration_strategy.on_delete/2,
      expire?: &expiration_strategy.expire?/2,
      entries: %{},
      refresh_strategy: refresh_strategy,
      expiration_strategy: expiration_strategy
    }

    state = expiration_strategy.init(state)

    {:ok, state}
  end

  @doc false
  def handle_call({:put, key, value}, _from, state) do
    state =
      state
      |> run_callback(:on_write, {key, value})
      |> put_in([:entries, key], value)

    {:reply, :ok, state}
  end

  @doc false
  def handle_call({:get, key}, _from, state) do
    state = run_callback(state, :on_read, key)
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

  def handle_info({:expire, {key, metadata}}, state) do
    if run_callback(state, :expire?, {key, metadata}) do
      run_callback(state[:on_expire], {key, state[:entries][key]})
      {:noreply, delete_key(key, state)}
    else
      {:noreply, state}
    end
  end

  defp delete_key(key, state) do
    state
    |> update_in([:entries], fn entries -> Map.delete(entries, key) end)
    |> run_callback(:on_delete, key)
  end

  defp update_key_state(key, :TTLCache_delete, state) do
    update_in(state[:entries], fn map -> Map.delete(map, key) end)
  end

  defp update_key_state(key, value, state) do
    state
    |> run_callback(:on_write, {key, value})
    |> put_in([:entries, key], value)
  end

  defp run_callback(nil, _), do: :ok
  defp run_callback(callback, arg) when is_function(callback), do: callback.(arg)
  defp run_callback(state, key, args), do: state[key].(state, args)
end
