defmodule TTLCache.Expiration do
  @callback init(state :: map) :: state :: map
  @callback on_write(state :: map, {key :: term, value :: term}) :: state :: map
  @callback on_read(state :: map, key :: term) :: state :: map
  @callback on_delete(state :: map, key :: term) :: state :: map
  @callback expire?(state :: map, {key :: term, metadata :: term}) :: true | false
end

defmodule TTLCache.Expiration.SendAfter do
  @moduledoc """
  Callback module for implementing key expiration via Process.send_after. This approach
  works by using the BEAM's internal scheduling expire keys. Process.send_after will
  wait for some period of time and then send a message to the cache server. The cache
  server is configured to handle :expire messages and will delegate back to this module
  which will ensure that we're properly filtering out irrelevant expire messages (i.e.
  when we "refresh" the expiration we are just incrementing a pointer/watermark and we
  ignore any previous messages)
  """

  @behaviour TTLCache.Expiration

  def init(state) do
    put_in(state[:watermarks], %{})
  end

  def on_write(state = %{refresh_strategy: strat}, {key, _val}) when strat == :on_write or strat == :on_read_write do
    new_watermark = Map.get(state[:watermarks], key, -1) + 1
    Process.send_after(self(), {:expire, {key, new_watermark}}, state.ttl)
    put_in(state[:watermarks][key], new_watermark)
  end

  def on_write(state, {key, _val}) do
    if key not in Map.keys(state.entries) do
      Process.send_after(self(), {:expire, {key, nil}}, state.ttl)
    end

    state
  end

  def on_read(state = %{refresh_strategy: strat}, key) when strat == :on_read or strat == :on_read_write do
    new_watermark = Map.get(state[:watermarks], key, -1) + 1
    Process.send_after(self(), {:expire, {key, new_watermark}}, state.ttl)
    put_in(state[:watermarks][key], new_watermark)
  end

  def on_read(state, _) do
    state
  end

  def expire?(state, {key, watermark}) do
    if state.refresh_strategy != :never do
      Map.has_key?(state.entries, key) && watermark == get_in(state, [:watermarks, key])
    else
      Map.has_key?(state.entries, key)
    end
  end

  def on_delete(state, key) do
    update_in(state[:watermarks], &Map.delete(&1, key))
  end
end
