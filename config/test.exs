import Config

# The pre-existing router/deviation/policy suites exercise the ungated paths;
# test/beam4pm_admission_default_test.exs switches to :required explicitly via
# Application.put_env and restores this value.
config :beam4pm, :admission_mode, :skip

# Bandit listeners must never bind fixed ports (4210/4211) during test runs:
# two concurrent lanes hit :eaddrinuse because the ports may be held by a
# long-lived VM on this host. Port 0 = OS-assigned ephemeral port
# (BeamPM.Application reads :ocel_ingest_port/:a2a_port via
# Application.get_env; Bandit/Thousand Island binds port 0 fine).
config :beam4pm, ocel_ingest_port: 0, a2a_port: 0
