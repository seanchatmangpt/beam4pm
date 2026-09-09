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
