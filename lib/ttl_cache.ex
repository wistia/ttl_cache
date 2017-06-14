defmodule TTLCache do
  use Application

  def start(_, _) do
    TTLCache.Supervisor.start_link(name: TTLCache.Supervisor.Global)
  end
end
