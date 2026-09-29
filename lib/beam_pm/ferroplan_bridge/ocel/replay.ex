defmodule BeamPM.FerroplanBridge.Replay do
  alias BeamPM.FerroplanBridge.Receipt
  def deterministic?(a, b), do: Receipt.replay_key(a) == Receipt.replay_key(b) and a.provider == b.provider
end
