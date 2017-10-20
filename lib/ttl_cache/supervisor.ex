defmodule TTLCache.Supervisor do
  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, [], opts)
  end

  def init(_) do
    children = [
      worker(TTLCache.Server, [
        [ttl: Application.fetch_env!(:ttl_cache, :ttl)],
        [name: TTLCache.Server.Global]
      ])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
