import Config

# The pre-existing router/deviation/policy suites exercise the ungated paths;
# test/beam4pm_admission_default_test.exs switches to :required explicitly via
# Application.put_env and restores this value.
config :beam4pm, :admission_mode, :skip
