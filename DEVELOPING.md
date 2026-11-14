# Developing

How I set up a machine, build the project and check a change. The rules for
branches, commits and pull requests are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Set up

You need Linux with KVM and about 10 GB of free memory.

```bash
mise install    # just, D2, uv, kubectl, Helm, mdBook, gitleaks, cargo-llvm-cov
just bench      # checks the tools mise doesn't install
```

Rust is pinned in `rust-toolchain.toml`, with the `thumbv7em-none-eabihf`
target. Multipass, Renode, probe-rs and the ClickHouse client are installed by
hand.

## Build and test

```bash
just lint       # rustfmt, Clippy and Ruff, warnings as errors
just test       # host tests, a firmware build and the bbcheck tests
just coverage   # line coverage across Rust and Python
```

The host crates (`gateway/`, `pipeline/`) share the root workspace. The
firmware has its own workspace in `firmware/`, because it only builds for the
microcontroller. bbcheck is a uv project in `tools/bbcheck/`.

## Docs and diagrams

```bash
just diagrams   # render every D2 file in docs/diagrams/
just docs       # build the site into book/
```

## Before I push

```bash
just audit      # secrets and blocked terms
```

CI runs the same recipes, so a green run here means a green run there.

## Releases

release-please opens a release pull request from the commits on `main`.
Merging it bumps every version, writes the changelog and tags the release. See
[changelog.d](changelog.d/README.md).
