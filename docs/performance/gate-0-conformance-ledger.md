# Gate 0 conformance-ledger performance contract

## Scope

This slice adds build-time data and Python schema checks. It adds no production
Roc value, runtime lookup, or generated-PDF work.

## Representation and ownership

- Sources, capabilities, profiles, and requirements are flat JSON arrays with
  stable string identities. Requirement-to-source and requirement-to-capability
  relationships are scalar identity lists; source records are not duplicated.
- The checker owns each parsed document for one process invocation. Its derived
  dictionaries and sets contain only coarse ledger entries and are released at
  process exit.
- The production package does not retain the standards prose, JSON parse trees,
  URLs, or verification metadata.

## Complexity and deterministic work

Validation is linear in source, capability, profile, requirement, relationship,
and scenario-reference counts, plus sorting of the small identity lists already
required to be stored in canonical order. It performs no network access and its
result depends only on checked-in bytes and repository paths.

The test harness runs the checker before invoking Roc. Therefore checker
allocations and work cannot affect any Roc allocation boundary, PDF byte
snapshot, or production retained-memory result.

## Gate evidence

`scripts/check_contracts.py --self-test` validates the checked-in corpus and
then proves that an altered EC3 digest, facade mapping, capability availability,
source reference, or individually pinned errata rule is rejected. The existing
Roc profile expects remain the independent executable check of the public typed
mapping.
