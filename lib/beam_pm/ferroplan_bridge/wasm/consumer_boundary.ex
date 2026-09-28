defmodule BeamPM.FerroplanBridge.ConsumerBoundary do
  def request(subject, capability, payload) when is_binary(subject) and subject != "" do
    %{subject: subject, capability: capability, payload: payload, authority: :none}
  end
end
