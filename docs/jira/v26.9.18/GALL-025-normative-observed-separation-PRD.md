# PRD v26.9.18 — GALL-025: Normative / Observed Separation

**Status:** DRAFT IMPLEMENTATION SPEC  
**Release:** v26.9.18  
**Repository:** `seanchatmangpt/beam4pm`  
**Owner:** beam4pm  
**Dependencies:** GALL-016 POWL, GALL-024 OCEL observation  
**Authority ceiling:** COMPARE/OBSERVE only

## Product outcome
beam4pm stores and compares normative process law and observed OCEL as distinct subjects, emitting deviations/findings without allowing observations to mutate the normative model.

## Problem
Observed behavior often diverges from normative process law. Automatically rewriting the law to match observations erases the very deviations process intelligence must detect.

## Functional requirements
1. Bind normative POWL/process-law subject and observed OCEL subject independently.
2. Represent comparison output as findings/deltas with explicit evidence class.
3. No observed event or discovered model may overwrite normative source.
4. Support cases where observation is valid reality but nonconformant to law.
5. Support law-version changes as new admitted subjects, not implicit updates.
6. Expose findings downstream as candidate evidence only.

## Acceptance criteria
1. Observed compliant fixture yields no load-bearing deviation.
2. Observed noncompliant fixture yields typed finding while normative digest stays unchanged.
3. Attempted observer-driven normative mutation fails architecture/test guard.
4. Changing normative version changes comparison subject.
5. Changing observation changes finding subject without changing law identity.
6. Finding is consumable by GALL-026/029 as candidate evidence.

## Evidence product
Emit a content-addressed receipt binding exact source/query/process/module/runtime identities, positive witness, attempted falsifiers, outputs and evidence ceiling. Portability means semantic identity, not merely successful execution.

## Definition of done
beam4pm stores and compares normative process law and observed OCEL as distinct subjects, emitting deviations/findings without allowing observations to mutate the normative model.
