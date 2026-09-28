defmodule BeamPM.FerroplanBridge.VkgConsumer do
  def request(binding, contract, subject), do: %{source: binding.id, origin: binding.origin, digest: binding.digest, contract: contract.id, subject: subject}
end
