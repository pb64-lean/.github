# pb64-lean CI: architecture and runner runbook

## Architecture

- **Shared engine (this repo)**: reusable workflows
  [`bazel-ci.yml`](../.github/workflows/bazel-ci.yml) (hermetic
  `bazel test` on self-hosted runners),
  [`integration.yml`](../.github/workflows/integration.yml) (docker-backed
  integration scripts), and [`assurance.yml`](../.github/workflows/assurance.yml)
  (GitHub-hosted static scan), plus the
  [`checkout-siblings`](../actions/checkout-siblings/action.yml) composite
  action that reproduces the side-by-side checkout layout Bzlmod
  `local_path_override` requires.
- **Per-repo callers**: each repository has a thin `.github/workflows/ci.yml`
  (and, where applicable, `pg-live.yml` / `e2e.yml`) that calls the engine
  with its sibling list.

## Security model (public repos + self-hosted runners)

The runner machines also host private services, so fork-supplied code must
never execute on them. Layers:

1. **Trigger discipline**: every job with a `self-hosted` label triggers only
   on `push` to `main`, `schedule`, or `workflow_dispatch`. `pull_request`
   jobs exist only for the GitHub-hosted assurance scan and meta-lint. The
   reusable workflows additionally hard-fail on pull_request events.
2. **Org Actions settings** (Settings → Actions → General):
   - Fork pull request workflows: **Require approval for all outside
     collaborators**.
   - Workflow permissions: **Read repository contents** (read-only
     `GITHUB_TOKEN`); do not allow Actions to create/approve PRs.
   - Allowed actions: org-owned plus `actions/*` (checkout, upload-artifact).
   - Runner groups → Default: **enable "Allow public repositories"** —
     without it, org runners refuse jobs from the public repos and everything
     queues forever.
3. **Runner isolation**: dedicated system users (`gh-runner-hermetic`,
   `gh-runner-integration`), no sudo/wheel, `ProtectHome` on (jobs cannot
   read `/home/*`). Only the integration runner is in the `docker` group
   (docker ≈ root; the hermetic runner, which executes most jobs, has no
   socket access).

## Runners and labels

Two persistent org-level runners per machine:

| Labels | User | Purpose |
| --- | --- | --- |
| `self-hosted, nixos, <host>, lean-hermetic` | gh-runner-hermetic | `bazel test //...` jobs (no docker) |
| `self-hosted, nixos, <host>, lean-integration, docker` | gh-runner-integration | docker/compose integration jobs |

One job per runner at a time is the serialization mechanism for the fixed
host ports (54397/54398 acme compose, 54399 pg-live, 50153 grpcurl interop)
and the fixed compose project name (`lean-acme-widgets`). Workflows select by
capability label (`lean-hermetic` / `lean-integration`), never by host.

Runner PATH must provide: `bazel` 8.5.0, `nix-build`/`nix-store`, `git`,
`docker` + `docker compose` (integration), `grpcurl`, `nc`, `openssl`,
`curl`, `jq`, coreutils. On NixOS this is the `extraPackages` list in the
`github-runners.nix` module; keep it stable — the runner PATH feeds Bazel's
action environment and thus its cache key.

## Registration (org-level)

1. Create a **fine-grained PAT**: github.com → Settings → Developer settings
   → Fine-grained tokens; Resource owner `pb64-lean`; expiry ≈ 1 year;
   Organization permissions → **Self-hosted runners: Read and write** (only).
   (Org Settings → Third-party Access must allow fine-grained PATs.)
2. Store it via sops as `github_runner_pat` in the host's secrets; the NixOS
   `services.github-runners` module exchanges a PAT for registration tokens
   automatically, so re-registrations survive without manual refresh.
3. `nixos-rebuild switch`; verify with
   `curl -s -H "Authorization: Bearer $PAT" https://api.github.com/orgs/pb64-lean/actions/runners | jq '.runners[] | {name, status, labels: [.labels[].name]}'`.

## The Lean toolchain and caches

- The repos build Lean `4.31.0-pre-24bef91` from source via `nix-build`
  (rules_lean's `nix_toolchain`); public binary caches cannot serve it. A
  runner without a pre-seeded store path requires ~1–2 h to build it. The
  runner module lists the identical pinned derivation in
  `environment.systemPackages`, which makes the system profile a permanent
  GC root, so nix GC cannot collect the toolchain.
- Each machine runs a `bazel-remote` cache on `127.0.0.1:9092` (HTTP,
  100 GB LRU). The engine probes it per run and degrades gracefully.
- Weekly hygiene (systemd timers): Sunday 04:00 restart idle runners (the
  service wipes its work dir on start, discarding checkouts and output
  bases; the next build re-warms from bazel-remote), 05:00 `nix.gc`,
  06:00 `nix.optimise`. An hourly disk guard force-prunes below 30 GiB free.

## Provisioning a NixOS runner host

1. **Pre-seed the toolchain** (optional): on an existing runner, set
   `LEAN=$(nix-build /etc/nixos/nix/pkgs/lean4 --no-out-link)`, then copy that
   store path to the target host with
   `sudo nix copy --no-check-sigs --from ssh://<existing-runner> "$LEAN"`.
   Without pre-seeding, the 240-minute job timeout covers the source build.
2. **sops**: on the target host, generate or read the age key
   (`sudo age-keygen -y /var/lib/sops-nix/key.txt`), add the recipient to
   `.sops.yaml`, run `sops updatekeys secrets.yaml`, commit.
3. **Host prerequisites**: configure `virtualisation.docker.enable`, the
   `programs.nix-ld` block, the `/bin/bash` activation-script shim, and
   `security.allowUserNamespaces = true` +
   `boot.kernel.sysctl."kernel.unprivileged_userns_clone" = 1`
   (Bazel's linux-sandbox needs user namespaces).
4. Import `github-runners.nix` into the target host configuration, rebuild,
   and verify both host runners online in organization settings.

## Known failure modes

| Failure | Mitigation |
| --- | --- |
| Runner offline → jobs queue forever | `Restart=on-failure` on the services; check `.runners[].status` via the API; two machines give redundancy |
| Disk exhaustion mid-build | engine's 20 GiB fail-fast guard; hourly 30 GiB force-prune; weekly workdir wipe; bazel-remote LRU cap |
| OOM (no swap) | `ci.slice` MemoryHigh/Max + `ManagedOOMMemoryPressure=kill` makes CI the designated victim; `--local_resources=memory=40960` keeps Bazel under the ceiling |
| Nix GC collects the toolchain | impossible while the system-profile GC root exists (see above) |
| Orphaned docker containers after a timeout-kill | `integration.yml`'s `always()` cleanup step removes `pg-lean-live-*` containers and the `lean-acme-widgets` compose project's containers/volumes/networks |
| Sibling `main` regression reddens downstream repos | intended integration signal; weekly schedules surface it without pushes |
| Timing-flaky grpcurl deadline check | `--flaky_test_attempts=3` on the interop job: transient losses report FLAKY (green), persistent failures stay red |
