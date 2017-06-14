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
