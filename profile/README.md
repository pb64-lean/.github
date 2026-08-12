# pb64-lean

**Lean 4 as a systems-programming and verified-interface language.**

Eight project repositories form one ecosystem: Bazel-native Lean build
tooling, Protocol Buffers code generation, a pure-Lean gRPC runtime over
HTTP/2, refinement-typed protobuf validation, compile-time dependency
injection with environment-backed configuration, checked PostgreSQL DDL/query
code generation, a PostgreSQL client, TLS 1.3 over HACL\* verified
cryptographic primitives, and an integrated example service.

**Start with [`lean-acme-widgets`](https://github.com/pb64-lean/lean-acme-widgets)** —
the example service that integrates the ecosystem. **The defining
verified-interface pattern is implemented by
[`protovalidate-lean`](https://github.com/pb64-lean/protovalidate-lean)**:
externally declared CEL constraints (buf.validate) compiled into ordinary
Lean subtypes and dependent propositions, with proof-carrying values
constructed at the decode/validation boundary — so handlers consume data
whose validation and policy evidence is machine-checked.

## Repositories, in reading order

| # | Repository | What it is |
| --- | --- | --- |
| 1 | [`lean-acme-widgets`](https://github.com/pb64-lean/lean-acme-widgets) | Example CRUD service: Lentil-composed configuration and startup + gRPC + refinement-typed validation + PostgreSQL persistence + TLS, with scripted plaintext and TLS end-to-end scenarios (CRUD, policy denials, `verify-full`, graceful shutdown) |
| 2 | [`protovalidate-lean`](https://github.com/pb64-lean/protovalidate-lean) | Go protoc plugin + Lean runtime compiling a documented subset of buf.validate CEL rules into field subtypes and dependent message propositions; generated `validate`/`decodeValid` construct proof-carrying values |
| 3 | [`grpc-lean`](https://github.com/pb64-lean/grpc-lean) | Protobuf codegen and a pure-Lean gRPC client/server runtime over HTTP/2: all four RPC shapes (batched and incremental streaming), deadlines, pre-body header authorization, gzip, health + reflection services, TLS termination |
| 4 | [`lean-pgx`](https://github.com/pb64-lean/lean-pgx) | Bazel-native PostgreSQL DDL/query contract generation: replays declared migrations against pinned PostgreSQL 17/18, emits typed Lean APIs plus canonical schema/constraint IR and proof-producing validators, and verifies live attachment and query descriptors |
| 5 | [`pg-lean`](https://github.com/pb64-lean/pg-lean) | PostgreSQL client: pure-Lean wire protocol (3.0/3.2), SCRAM-SHA-256(-PLUS) with channel binding, TLS with `verify-full`, COPY, pipelining, notifications; live-tested against PostgreSQL 17 and 18 |
| 6 | [`tls13-lean`](https://github.com/pb64-lean/tls13-lean) | TLS 1.3 client/server machinery in Lean over HACL\* verified crypto via an explicit C FFI; sans-I/O engines, X.509 path validation, channel binding, ChaCha20-Poly1305, X25519, optional P-256, and Ed25519 |
| 7 | [`lentil`](https://github.com/pb64-lean/lentil) | Compile-time dependency injection for Lean 4: `@[lentil]` recipes, elaboration-time graph validation and planning, generated shared contexts, and `@[lentil_config]` environment-backed configuration beans |
| 8 | [`rules_lean`](https://github.com/pb64-lean/rules_lean) | Bazel/Bzlmod rules for Lean 4: `lean_library`/`lean_binary`/`lean_test`, locked Lake dependency import, C interface export, portable static Linux executables |

## Checking out and building

Every project builds with Bazel. The integrated Acme service builds from a
side-by-side set of seven co-developed repositories; its six sibling
dependencies are wired through Bzlmod `local_path_override`, while Lentil is
fetched from a checksummed public archive. Lentil's own standalone build
likewise fetches its `rules_lean` dependency from a checksummed public archive.
To build the integrated service:

```sh
for r in rules_lean grpc-lean protovalidate-lean tls13-lean pg-lean lean-pgx lean-acme-widgets; do
  git clone "https://github.com/pb64-lean/$r"
done
cd lean-acme-widgets
bazel test //...
```

Prerequisites: Bazel 8.5 (every repo pins `.bazelversion`; bazelisk
recommended) and **Nix** (the Lean toolchain is nix-built). The live
end-to-end scripts additionally use Docker Compose, `grpcurl`, and
`openssl`.

## Build and toolchain contract

- **Canonical build and test tool: Bazel** via `rules_lean`.
  `bazel test //...` in each repository is the validation command.
- **Canonical compiler: Lean `4.31.0-pre-24bef91`**, built by Nix from a
  pinned nixpkgs revision plus a `lean4_upstream_std` overlay (the
  pinned compiler provides the required `Std.Async` networking modules).
  Five repositories consume the overlay from
  `grpc-lean/third_party/Lean-zh/protobuf/nixpkgs.{nix,json}`; `rules_lean`
  carries its own copy of the same pin, and `lean-pgx` and Lentil request that
  matching toolchain through `rules_lean`.
- **`lean-toolchain` files are editor/elan selectors only** — no Bazel build
  reads them. Every project repository selects the `nightly-2026-04-25`
  editor toolchain corresponding to the Bazel compiler pin. Lentil uses the
  equivalent `leanprover/lean4:nightly-...` spelling; the other checkouts use
  `leanprover/lean4-nightly:nightly-...`.
- **Lakefiles primarily provide IDE project models** (they let `lake serve`
  resolve module graphs and sibling imports). Every project except
  `rules_lean` has one; Bazel remains the authoritative build and test path,
  and generated-code and integration paths remain Bazel-only.
- **Compatibility**: all modules currently use `0.1.0` as a development
  coordinate. Dependency resolution is owned by each root: the integrated
  stack primarily uses `local_path_override`, while standalone boundaries can
  use checksummed public archives (including Lentil → `rules_lean` and Acme →
  Lentil). Registry releases, version tags, and cross-version compatibility
  are not yet part of the published compatibility contract.

## CI

Hermetic `bazel test //...` runs for every repository on self-hosted NixOS
runners (push to `main`, weekly, and on demand), including the grpcurl
interop suite for `grpc-lean`. `lean-pgx` exercises transient PostgreSQL
17/18 generation, cross-major compatibility, live generated APIs, and a
standalone downstream Bzlmod consumer; Lentil separately tests its own
standalone downstream Bzlmod consumer. Docker-backed suites cover the live
PostgreSQL 17/18 matrix for `pg-lean` (quick subset on push, the full
26-combination matrix weekly) and the Acme end-to-end scenarios (plaintext,
TLS, and in-process gRPC-over-TLS). A GitHub-hosted **assurance scan** runs on
every push and pull request: it fails on `sorry`, inventories
`axiom`/`unsafe`/`@[extern]`/`partial def`, handwritten C, and vendored trees,
and reports the toolchain and dependency pins.

| Repository | Hermetic | Integration | Assurance |
| --- | --- | --- | --- |
| lean-acme-widgets | [![CI](https://github.com/pb64-lean/lean-acme-widgets/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/pb64-lean/lean-acme-widgets/actions/workflows/ci.yml) | [![E2E](https://github.com/pb64-lean/lean-acme-widgets/actions/workflows/e2e.yml/badge.svg?branch=main)](https://github.com/pb64-lean/lean-acme-widgets/actions/workflows/e2e.yml) | [![Assurance](https://github.com/pb64-lean/lean-acme-widgets/actions/workflows/assurance.yml/badge.svg?branch=main)](https://github.com/pb64-lean/lean-acme-widgets/actions/workflows/assurance.yml) |
| protovalidate-lean | [![CI](https://github.com/pb64-lean/protovalidate-lean/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/pb64-lean/protovalidate-lean/actions/workflows/ci.yml) | — | [![Assurance](https://github.com/pb64-lean/protovalidate-lean/actions/workflows/assurance.yml/badge.svg?branch=main)](https://github.com/pb64-lean/protovalidate-lean/actions/workflows/assurance.yml) |
| grpc-lean | [![CI](https://github.com/pb64-lean/grpc-lean/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/pb64-lean/grpc-lean/actions/workflows/ci.yml) | (interop in CI) | [![Assurance](https://github.com/pb64-lean/grpc-lean/actions/workflows/assurance.yml/badge.svg?branch=main)](https://github.com/pb64-lean/grpc-lean/actions/workflows/assurance.yml) |
| lean-pgx | [![CI](https://github.com/pb64-lean/lean-pgx/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/pb64-lean/lean-pgx/actions/workflows/ci.yml) | (PG17/18 + downstream in CI) | [![Assurance](https://github.com/pb64-lean/lean-pgx/actions/workflows/assurance.yml/badge.svg?branch=main)](https://github.com/pb64-lean/lean-pgx/actions/workflows/assurance.yml) |
| pg-lean | [![CI](https://github.com/pb64-lean/pg-lean/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/pb64-lean/pg-lean/actions/workflows/ci.yml) | [![PG live](https://github.com/pb64-lean/pg-lean/actions/workflows/pg-live.yml/badge.svg?branch=main)](https://github.com/pb64-lean/pg-lean/actions/workflows/pg-live.yml) | [![Assurance](https://github.com/pb64-lean/pg-lean/actions/workflows/assurance.yml/badge.svg?branch=main)](https://github.com/pb64-lean/pg-lean/actions/workflows/assurance.yml) |
| tls13-lean | [![CI](https://github.com/pb64-lean/tls13-lean/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/pb64-lean/tls13-lean/actions/workflows/ci.yml) | — | [![Assurance](https://github.com/pb64-lean/tls13-lean/actions/workflows/assurance.yml/badge.svg?branch=main)](https://github.com/pb64-lean/tls13-lean/actions/workflows/assurance.yml) |
| lentil | [![CI](https://github.com/pb64-lean/lentil/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/pb64-lean/lentil/actions/workflows/ci.yml) | (downstream consumer in CI) | [![Assurance](https://github.com/pb64-lean/lentil/actions/workflows/assurance.yml/badge.svg?branch=main)](https://github.com/pb64-lean/lentil/actions/workflows/assurance.yml) |
| rules_lean | [![CI](https://github.com/pb64-lean/rules_lean/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/pb64-lean/rules_lean/actions/workflows/ci.yml) | — | [![Assurance](https://github.com/pb64-lean/rules_lean/actions/workflows/assurance.yml/badge.svg?branch=main)](https://github.com/pb64-lean/rules_lean/actions/workflows/assurance.yml) |

## Assurance boundary, briefly

The HACL\* cryptographic primitives carry externally machine-verified
correctness proofs and enter Lean through a small, explicit C shim with
`@[extern]` bindings.

The Lean protocol code combines executable tests (known-answer vectors,
live-server matrices, and end-to-end scenarios) with **kernel-checked laws
about the implementation itself**, rather than a parallel specification
model. Representative results:

- **TLS**: nonces never repeat within a traffic-secret epoch across a
  connection's emissions (resting on one named KDF-injectivity assumption,
  since HKDF is an opaque HACL\* binding); the record framer conserves
  bytes and is independent of how the stream is fragmented; handshake
  codecs round-trip with unknown/GREASE values preserved; a parsed
  ClientHello re-encodes to its own bytes, and retry processing preserves
  that exact-byte identity; the key schedule structurally refines RFC 8446
  §7.1;
  strict-DER exact-slice retention reaches the bytes certificate signatures
  are verified over.
- **PostgreSQL**: a pipelined client cannot misattribute a response — every
  user-visible success pops exactly the head operation, in submission
  order — plus `Sync`-recovery alignment, and codec round-trips including
  the lossless base-10000 numeric.
- **Generated PostgreSQL APIs**: declared DDL and literal SQL are replayed
  against PostgreSQL into canonical symbolic schema/query IR and typed Lean
  APIs. Generated validators construct proofs for the explicitly supported
  local constraint subset; attachment and prepared-query checks detect
  catalog and descriptor drift. An exact assurance target pins public theorem
  statements and the trust inventory, but does not prove arbitrary SQL,
  PostgreSQL behavior, or that a live database realizes the relational model.
- **gRPC**: RPC-shape agreement is structural rather than runtime-checked;
  a stream rejected at headers can never accept a body or reach a handler;
  flow-control credit is conserved; codec laws run up to HPACK Huffman
  `decode∘encode`.
- **Generated code**: every protovalidate-annotated message ships
  `validate_sound` / `validate_complete` theorems, and the example service
  binds its authorization propositions to an unfabricable authenticated
  principal.
- **Composition**: Lentil validates registered dependency graphs during
  elaboration and emits ordinary construction terms that Lean typechecks. It
  does not prove recipe semantics, runtime resource safety, or the correctness
  and secrecy of environment values.

What is **not** claimed: no refinement theorem against any RFC as a whole,
no security proofs, no timing analysis, nothing about the C shims beyond
their preconditions. Each repository's README states its own boundary, and
every project repository runs the static assurance workflow. In the proof-heavy
repositories, `lean_assurance_test` targets additionally audit the compiled
environment — axiom closures, `sorry` reachability, and `@[extern]`
inventories pinned to the exact modules allowed to contain them. tls13-lean,
pg-lean, and lean-pgx's audited `Pgx` module surface close over only `propext`,
`Classical.choice`, and `Quot.sound`.
