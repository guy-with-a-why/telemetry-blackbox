# 0005. just and mise over make, and a local registry for images

- **Status:** Accepted
- **Date:** 2026-11-12
- **Issue:** #37

## Context

I started with a Makefile to render the diagrams. It didn't last. Make is a
build tool, not a task runner: recipes need tabs, every task needs `.PHONY`
and shell variables need `$$`. Its strength is rebuilding files when their
inputs change, and cargo and uv already do that for their own code.

The project runs from firmware up to the cluster, so it spans four
ecosystems:

1. Rust, for the host crates and the firmware.
2. Python, for bbcheck and the scripts.
3. D2 and mdBook, for the docs.
4. kubectl and Helm, for the cluster.

Each has its own tooling and none of it covers the others. I need one entry
point that sits above all four.

CI must run the same tools at the same versions as my laptop. Otherwise a
check can pass in one place and fail in the other.

The constraints:

- Everything runs on one laptop with about 10 GB of free memory, shared by
  five VMs and Renode.
- Rust is pinned in `rust-toolchain.toml`, because rustup owns the toolchain
  and the firmware target.
- Multipass, Renode, probe-rs and the ClickHouse client are installed by
  hand. They don't fit a version manager.
- Images built on the host have to reach containerd on five VMs, many times a
  day while I iterate.
- I have four days, so the tooling has to be boring and quick to set up.

## Decision

- `just` runs every task. The justfile only calls programs and scripts, and
  the real logic lives in them.
- `mise` pins the CLI tools in `mise.toml`. CI installs from the same file
  with `jdx/mise-action`.
- A `registry:2` on the host carries images into the cluster, and containerd
  on every VM trusts it through `hosts.toml`. #10 builds it.

## Options I turned down

- **make.** It was my first choice. For the reasons above, I replaced it
  before the first pull request.
- **cargo xtask.** Tasks written in Rust suit a Rust-only repo. Here they would
  mostly wrap Python, D2 and Helm, and every change to a task means a compile.
- **asdf, or installing by hand.** asdf needs a plugin per tool. Hand installs
  drift, and CI stops matching my laptop.
- **Importing images by hand.** `ctr images import` has to run on each of five
  nodes. It's easy to leave one stale, and pods don't pull the way they would
  in production.
- **GHCR for every build.** Each build would need a push, credentials and the
  network. GHCR stays the release channel (#40). The local registry is for
  the inner loop.

## Consequences

- There are two more tools to learn. `mise install` brings `just`, so setup
  is still one step.
- The registry is one more process on the host, but it's small next to five
  VMs.
- The registry speaks plain HTTP on a private network. That's fine on a
  laptop and wrong anywhere else.
- Every task has one name, and CI runs the versions I run.
- Pods pull images as they would from a real registry, so `imagePullPolicy`
  behaves normally.
- I'd revisit this if the project moved to more than one machine, or if
  devcontainers or Nix took over the whole bench.

## References

- [The just manual](https://just.systems/man/en/)
- [The mise documentation](https://mise.jdx.dev/)
- [The Distribution registry](https://distribution.github.io/distribution/)
- [containerd registry hosts](https://github.com/containerd/containerd/blob/main/docs/hosts.md)
