# TTLCache

Caches a value and expires it after a given TTL.
Provides a callback for hooking into expiration

## Installation

```ex
def deps do
  {:ttl_cache, "~> 0.1", github: "wistia/ttl_cache"}
end
```

## Usage

See [TTLCache.Server](lib/ttl_cache/server.ex) for the latest documentation

```ex
{:ok, pid} = TTLCache.Server.start_link(ttl: 5_000, on_expire: fn {key, _val} -> IO.inspect("#{key} expired") end)
:ok = TTLCache.Server.put(pid, :hello, "world")
{:ok, "world"} = TTLCache.Server.get(pid, :hello)

:timer.sleep(5_000)
# should log

{:ok, nil} = TTLCache.Server.get(pid, :hello)
```

### Refresh Strategies

`TTLCache.Server` supports several refresh strategies:

* `:on_write` - refresh the TTL when the key is written to. Does not care whether or not the value changed
* `:on_read` - refresh the TTL when the key is read. Note that any update (including `get_and_update`) is considered a write
* `:on_read_write` - refresh the TTL when the key is written to or read
* `:never` - never refresh and just remove the key after the TTL

You can pass these strategies via `TTLCache.Server.start_link`:

```ex
TTLCache.Server.start_link(refresh_strategy: :on_write)
```
