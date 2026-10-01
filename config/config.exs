import Config

# Required by ash >= 3.33 (transitively pulled in by ash_ai 1.0.0's bump):
# Ash needs to know how to count string length for :string/:ci_string
# min_length/max_length constraints, the string_length validation, and the
# string_length/1 expression. :codepoints counts Unicode codepoints (correct
# for arbitrary text, including multi-byte characters) rather than :mixed's
# byte-oriented fast path -- this repo's admitted bpm:Field values are
# free-form strings (ids, hashes, digests, evidence text), so codepoint
# accuracy is the safer default absent a specific performance reason to
# switch to :mixed.
config :ash, default_string_length_count: :codepoints

# BeamPM.A2AAgent (lib/beam4pm_a2a_agent.ex) is booted by ash_a2a's own
# Application callback (AshA2A.Application, `:ash_a2a`'s `mod`), which reads
# this config and starts an A2A.AgentSupervisor for it -- so
# BeamPM.Application must NOT also start an A2A.AgentSupervisor for the same
# agent (that double-starts the agent's registered name and crashes boot).
# BeamPM.Application only adds the HTTP listener (A2A.Plug/Bandit) on top.
config :ash_a2a, :agents, [BeamPM.A2AAgent]
# OTel SDK exporter for BeamPM.Evidence.OtelBridge (lib/beam4pm_evidence.ex,
# OCEL evidence-contract Phase 3). beam4pm is a library/substrate, not a
# standalone service, so it should not force stdout tracing on every host
# application that depends on it -- default to the real, human-visible
# :otel_exporter_stdout processor in :dev/:test (matches this repo's own
# `mix test`/smoke-check workflow) and to :none in every other env unless a
# host app explicitly overrides `config :opentelemetry, traces_exporter:
# ...` for its own deployment (a real OTLP exporter dep, added by that host
# app, not by beam4pm itself).
if Mix.env() in [:dev, :test] do
  config :opentelemetry,
    traces_exporter: {:otel_exporter_stdout, []}
else
  config :opentelemetry, traces_exporter: :none
end

# Admission mode (BeamPM.GraphlawAdmission.mode/0): :required (default,
# fail-closed) makes ReplanRouter :session_replan, ReplanRouter.load_policy/4
# and DeviationAdmission.admit_deviation/5 run the graphlaw court unless the
# call opts out (`admission: :skip`, `graphlaw_court: false`,
# `graphlaw_gate: false`); :skip disables the default gating for the whole VM.
config :beam4pm, :admission_mode, :required

# ash_ex4pm pulls ex4pm, whose Ex4pm.Application (deps/ex4pm/lib/ex4pm/
# application.ex) starts Ex4pm.Evidence.Store -- the receipt ledger sink that
# Ex4pm.Stream.Ingest.ingest_envelope/1 (called by ex4pm's own notifiers) and
# ash_ex4pm's persist notifiers receipt into -- and it MUST keep starting.
# The same callback also starts ex4pm's OWN wasm hosts (Ex4pmEngine.Wasm.Host
# + Ex4pm.Engine.Ferroplan.Host) whenever `:wasm_host` is true (the default).
# beam4pm already hosts its own wasm engines under BeamPM.EngineSupervisor
# (lib/beam4pm_application.ex: engine_supervisor/0, gated by
# BeamPM.GraphlawAdmission.engine_children/0), so the second host tree is
# disabled here to keep exactly one wasm host per node.
config :ex4pm, wasm_host: false

# Per-env overrides (config/test.exs keeps the pre-existing ungated suites
# running; the admission-default tests switch the mode explicitly).
if File.exists?(Path.expand("#{config_env()}.exs", __DIR__)) do
  import_config "#{config_env()}.exs"
end
