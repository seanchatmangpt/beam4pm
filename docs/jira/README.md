# Jira-style implementation programs

This directory indexes versioned implementation backlogs and doctrine packages maintained as
repository-native Markdown, matching the convention used across the ggen ecosystem's sibling
repositories.

| Version | Program | Standing | Scope |
|---|---|---|---|
| [`v26.8.29/`](./v26.8.29/) | beam4pm / beam4pm_pro ggen-only manufacturing charter and cloud-marketplace RevOps package | `PARTIAL_ALIVE` — documentation bootstrap only; no runtime, manufacturing, or marketplace-listing evidence yet | 15-document charter: product/architecture doctrine, source-authority governance, Rust4PM reference boundary, institutional-legibility vision, cloud marketplace RevOps, pricing/packaging, GTM/sales, security/air-gap, roadmap, epics/stories, TAI quality operations, portfolio monetization strategy, and release gates/receipts. |

## Standing law

A directory entry is an index, not proof that its program is complete. Read the program's own
`README.md` and the receipts/gates it names before assigning `ALIVE` standing to anything inside
it. See `v26.8.29/11-release-gates-receipts.md` for the standing vocabulary this repository uses
and its falsifier policy.

## beam4pm source-authority handoff

The beam4pm sequence, once manufacturing begins, is:

```text
admitted ontology/specification (O*)
  -> ggen manufacturing (mu)
  -> generated Erlang/Gleam/Elixir/Ash projections (A)
  -> Chicago-verified tests/examples/playground
  -> receipts and replay
```

Human and LLM direct application-source commits are refused by default; see
`v26.8.29/02-product-requirements.md` and `v26.8.29/03-architecture-and-ggen-manufacturing.md` for
the full source-lock doctrine and its narrow, receipted break-glass exception.
