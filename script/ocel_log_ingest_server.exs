# Standalone isolated-court harness: boots ONLY the OCEL 2.0 whole-log ingest
# surface (BeamPM.OcelLogStore + BeamPM.OcelLogIngest) behind Bandit on
# port 4212 -- no Ash domain, no A2A agent, no engines. Lawful when the full
# BeamPM.Application boot is blocked by unrelated dependency config (witnessed:
# ash_a2a SecurityProfile dev-config issue). Run:
#
#   cd /Users/sac/beam4pm && mix run script/ocel_log_ingest_server.exs
#
# then POST /api/ocel/ingest (valid -> 201 {"accepted":N,...}, malformed -> 422).
port = Application.get_env(:beam4pm, :ocel_log_ingest_port, 4212)

{:ok, _} = Supervisor.start_link(
  [
    {BeamPM.OcelLogStore, []},
    Supervisor.child_spec({Bandit, plug: BeamPM.OcelLogIngest, port: port}, id: :ocel_log_bandit)
  ],
  strategy: :one_for_one,
  name: BeamPM.OcelLogIngestStandaloneSupervisor
)

IO.puts("ocel_log_ingest listening on :#{port} (standalone court harness)")
Process.sleep(:infinity)
