# Gate 0 asset-provenance performance contract

## Scope

The provenance manifest describes versioned repository assets. Its validation
is test-only and adds no production Roc data, startup work, or generated-PDF
retention.

## Representation and ownership

- Each retained asset has one flat record. Reuse sites refer to the asset path;
  they do not copy provenance records or payload bytes.
- External assets require an immutable upstream revision, source URL, SHA-256
  digest, license, attribution, and explicit modification and redistribution
  permissions.
- Generated assets identify their checked-in generator and carry the same
  digest, size, license, attribution, and permission fields.
- Future hyphenation assets additionally require a BCP 47 language tag. No
  unversioned system dictionary is an acceptable origin.

## Complexity and deterministic work

The checker hashes every tracked binary asset once, so work is linear in total
retained asset bytes. It builds one small path map and compares it with the
tracked binary path set. It performs no network access and does not copy asset
payloads into the production package.

The check runs before every Roc allocation boundary. Consequently its hashing,
filesystem, Python, and Git work cannot affect Roc allocations, PDF bytes, or
production peak memory.

## Gate evidence

The schema self-test proves that a changed asset digest is rejected. The normal
check also rejects missing files, byte-length changes, unmanifested tracked
binary assets, duplicate identities or paths, mutable external origins, and a
hyphenation record without a language.
