//! oracle-io: the one piece of the rf1-rf4 (native/) and rust4pm-oracle
//! (qualification/) differential-testing oracle binaries' stdin wire
//! contract that was already byte-identical across all five crates,
//! modulo the oracle name embedded in the error string -- read all of
//! stdin as UTF-8, then `serde_json`-parse it into the caller's own
//! `WireInput` type.
//!
//! Deliberately bounded/local, not a "shared CLI harness": a wider
//! unification (one shared dispatch loop over each crate's `op` match) was
//! examined and refused as a phase-change, because rf1/rf2/rf4's flat
//! `WireInput { op: String, .. }` + runtime `match op.as_str()` and rf3's
//! `#[serde(tag = "op")] enum WireInput` are a genuine structural
//! difference in HOW an op is dispatched, not just naming -- forcing one
//! shape onto the other is a real cost for a small saving. This crate
//! takes none of that: [`read_stdin_json`] is generic over `T` and does
//! not know or care whether `T` is a flat struct or a tagged enum, so it
//! covers both shapes for free without touching any crate's dispatch
//! logic, op set, or WireInput definition.
//!
//! One deliberate, harmless normalization: rf3-ocel-oracle's prior inline
//! block said "malformed wire input JSON" where the other four say
//! "malformed input JSON" -- a wording-only divergence with no test
//! anywhere asserting the exact string (verified by repo-wide grep before
//! this crate was extracted). This crate's single message is used by all
//! five callers now; nothing keys off which oracle produced it.

use std::io::Read;
use std::process::ExitCode;

/// Reads all of stdin as UTF-8, then parses it as JSON into `T`.
///
/// On a stdin read failure or a JSON parse failure, prints
/// `"<oracle_name>: <problem>: <error>"` to stderr and returns
/// `Err(ExitCode::from(1))` -- every caller's own `main() -> ExitCode`
/// already returns whatever `ExitCode` it's handed on this path, so the
/// call site becomes:
///
/// ```ignore
/// let input: WireInput = match oracle_io::read_stdin_json("my-oracle") {
///     Ok(v) => v,
///     Err(code) => return code,
/// };
/// ```
pub fn read_stdin_json<T: serde::de::DeserializeOwned>(oracle_name: &str) -> Result<T, ExitCode> {
    let mut raw = String::new();
    if let Err(e) = std::io::stdin().read_to_string(&mut raw) {
        eprintln!("{oracle_name}: failed to read stdin: {e}");
        return Err(ExitCode::from(1));
    }
    parse_json(oracle_name, &raw)
}

/// The real parse step `read_stdin_json` runs on whatever it read from
/// stdin -- split out (not duplicated) so tests can drive it with real
/// in-memory JSON without needing to redirect the test process's own
/// stdin, which `read_to_string` above is the only stdin-touching line.
fn parse_json<T: serde::de::DeserializeOwned>(oracle_name: &str, raw: &str) -> Result<T, ExitCode> {
    serde_json::from_str(raw).map_err(|e| {
        eprintln!("{oracle_name}: malformed input JSON: {e}");
        ExitCode::from(1)
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    // Chicago-style: calls the crate's own real `parse_json` (the exact
    // function `read_stdin_json` delegates to after reading stdin) against
    // real JSON strings and real serde_json -- no mock of either. Reading
    // real process stdin is the one line left untested here by
    // construction (an in-process unit test cannot redirect its own
    // stdin per-case without a mock); it is covered end-to-end instead by
    // each of the five real oracle binaries' own qualification suites,
    // which pipe real bytes through a real spawned process.

    #[derive(Deserialize, Debug, PartialEq)]
    struct Flat {
        op: String,
        n: u32,
    }

    #[derive(Deserialize, Debug, PartialEq)]
    #[serde(tag = "op")]
    enum Tagged {
        A { n: u32 },
        B {},
    }

    #[test]
    fn generic_over_a_flat_struct() {
        let parsed: Flat =
            parse_json("test", r#"{"op":"x","n":7}"#).expect("valid flat JSON parses");
        assert_eq!(
            parsed,
            Flat {
                op: "x".to_string(),
                n: 7
            }
        );
    }

    #[test]
    fn generic_over_a_tagged_enum() {
        // Same real parse path, a structurally different WireInput shape
        // (rf3's #[serde(tag = "op")] enum) -- proves the function is
        // genuinely shape-agnostic, not merely "happens to compile" for
        // one caller.
        let parsed: Tagged =
            parse_json("test", r#"{"op":"A","n":3}"#).expect("valid tagged JSON parses");
        assert_eq!(parsed, Tagged::A { n: 3 });
        let parsed: Tagged = parse_json("test", r#"{"op":"B"}"#).expect("valid tagged JSON parses");
        assert_eq!(parsed, Tagged::B {});
    }

    #[test]
    fn malformed_json_is_a_real_parse_error() {
        let result: Result<Flat, ExitCode> = parse_json("test", "not json at all");
        assert_eq!(result, Err(ExitCode::from(1)));
    }
}
