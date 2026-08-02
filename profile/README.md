# pb64-lean

**Lean 4 as a systems-programming and verified-interface language.**

Six repositories form one ecosystem: Bazel-native Lean build tooling,
Protocol Buffers code generation, a pure-Lean gRPC runtime over HTTP/2,
refinement-typed protobuf validation, a PostgreSQL client, TLS 1.3 over
HACL\* verified cryptographic primitives, and an integrated example service.

**Start with [`lean-acme-widgets`](https://github.com/pb64-lean/lean-acme-widgets)** —
the example service that ties everything together. **The central original
idea is in [`protovalidate-lean`](https://github.com/pb64-lean/protovalidate-lean)**:
externally declared CEL constraints (buf.validate) compiled into ordinary
Lean subtypes and dependent propositions, with proof-carrying values
constructed at the decode/validation boundary — so handlers consume data
whose validation and policy evidence is machine-checked.

## Repositories, in reading order

| # | Repository | What it is |
| --- | --- | --- |
| 1 | [`lean-acme-widgets`](https://github.com/pb64-lean/lean-acme-widgets) | Example CRUD service: gRPC + refinement-typed validation + PostgreSQL persistence + TLS, with scripted plaintext and TLS end-to-end scenarios (CRUD, policy denials, `verify-full`, graceful shutdown) |
| 2 | [`protovalidate-lean`](https://github.com/pb64-lean/protovalidate-lean) | Go protoc plugin + Lean runtime compiling a documented subset of buf.validate CEL rules into field subtypes and dependent message propositions; generated `validate`/`decodeValid` construct proof-carrying values |
| 3 | [`grpc-lean`](https://github.com/pb64-lean/grpc-lean) | Protobuf codegen and a pure-Lean gRPC client/server runtime over HTTP/2: all four RPC shapes (batched and incremental streaming), deadlines, pre-body header authorization, gzip, health + reflection services, TLS termination |
| 4 | [`pg-lean`](https://github.com/pb64-lean/pg-lean) | PostgreSQL client: pure-Lean wire protocol (3.0/3.2), SCRAM-SHA-256(-PLUS) with channel binding, TLS with `verify-full`, COPY, pipelining, notifications; live-tested against PostgreSQL 17 and 18 |
| 5 | [`tls13-lean`](https://github.com/pb64-lean/tls13-lean) | TLS 1.3 client/server machinery in Lean over HACL\* verified crypto via an explicit C FFI; sans-I/O engines, X.509 path validation, channel binding (currently ChaCha20-Poly1305 / X25519 + optional P-256 / Ed25519) |
| 6 | [`rules_lean`](https://github.com/pb64-lean/rules_lean) | Bazel/Bzlmod rules for Lean 4: `lean_library`/`lean_binary`/`lean_test`, locked Lake dependency import, C interface export, portable static Linux executables |

## Checking out and building

Everything builds with Bazel, and the repositories expect side-by-side
checkouts (they reference each other with Bzlmod `local_path_override`):

```sh
for r in rules_lean grpc-lean protovalidate-lean tls13-lean pg-lean lean-acme-widgets; do
  git clone "https://github.com/pb64-lean/$r"
done
cd lean-acme-widgets
bazel test //...
```

Prerequisites: Bazel 8.5 (every repo pins `.bazelversion`; bazelisk
recommended) and **Nix** (the Lean toolchain is nix-built). The live
end-to-end scripts additionally use Docker Compose, `grpcurl`, and
`openssl`.

## The toolchain story, in one place

- **Canonical build and test tool: Bazel** via `rules_lean`.
  `bazel test //...` in each repository is the validation command.
- **Canonical compiler: Lean `4.31.0-pre-24bef91`**, built by Nix from a
  pinned nixpkgs revision plus a `lean4_upstream_std` overlay (the
  pre-release is needed for the newer `Std.Async` networking modules).
  Five repositories consume the overlay from
  `grpc-lean/third_party/Lean-zh/protobuf/nixpkgs.{nix,json}`; `rules_lean`
  carries its own copy of the same pin.
- **`lean-toolchain` files are editor/elan selectors only** — no Bazel build
  reads them. Most repos name `v4.27.0` for host editor tooling; `grpc-lean`
  names a local elan alias that `tools/link-lean-nix-toolchain.sh` links to
  the same nix-built 4.31-pre so the language server matches Bazel exactly.
- **Lakefiles are IDE project models only** (they let `lake serve` resolve
  the module graph and sibling imports). `lake build` is not a supported
  build path; `rules_lean` and `protovalidate-lean` have no lakefile at all.
- **Compatibility**: all modules are version `0.1.0` local-path
  developments. There are no published registry versions, tags, or
  cross-version guarantees yet.

## Assurance boundary, briefly

The HACL\* cryptographic primitives carry externally machine-verified
correctness proofs and enter Lean through a small, explicit C shim with
`@[extern]` bindings. The Lean protocol code — TLS state machines, HTTP/2,
the PostgreSQL wire protocol, gRPC — is implemented and tested
(known-answer vectors, live-server matrices, end-to-end scenarios) but is
not itself formally verified against the RFCs. The refinement-typed
validation layer produces machine-checked propositions about decoded
values; its supported CEL subset and semantic caveats are documented in
`protovalidate-lean`'s README, and each repository's README states its own
current limitations candidly (for example, the TLS server's narrow
ClientHello acceptance, and the example service's principal being supplied
by the client pending an authentication layer).
