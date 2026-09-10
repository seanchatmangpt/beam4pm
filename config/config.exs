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
