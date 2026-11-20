set shell := ["bash", "-euo", "pipefail", "-c"]

d2_flags := "--layout=elk --theme=0 --dark-theme=200 --pad=24"

# List every recipe
default:
    @just --list

# Check every bench tool is installed
bench:
    @for tool in just d2 uv node kubectl helm multipass docker renode cargo probe-rs clickhouse; do \
      if command -v "$tool" >/dev/null; then printf '%-10s ok\n' "$tool"; \
      else printf '%-10s missing\n' "$tool"; missing=1; fi; \
    done; exit "${missing:-0}"

# Render every diagram; files that declare steps are animated
diagrams:
    @for src in docs/diagrams/*.d2; do \
      extra=$(grep -q '^steps:' "$src" && echo --animate-interval=2000 || true); \
      d2 {{ d2_flags }} $extra "$src" "${src%.d2}.svg"; \
    done

# Scan the history for secrets
audit:
    gitleaks git --no-banner --redact .

# OSV-Scanner gets the lockfiles by name, so local worktrees and build output
# stay out of the scan. CI scans the whole checkout (ADR 7).

# Scan every lockfile for advisories, then check the crates' licences, bans and sources
vulns:
    osv-scanner scan source --lockfile Cargo.lock --lockfile firmware/Cargo.lock \
        --lockfile tools/bbcheck/uv.lock --lockfile tools/flight/package-lock.json
    cargo deny check bans licenses sources
    cd firmware && cargo deny --target thumbv7em-none-eabihf check bans licenses sources

# Build the docs site into book/: the README becomes its introduction, the
# flight strip and log come from the issues and the coverage badge from
# `just coverage`, if it has run. The introduction links the strips this build
# draws, not the ones last published
docs:
    sed -e 's#](docs/#](#g' -e 's#src="docs/#src="#g' -e 's#srcset="docs/#srcset="#g' \
        -e 's#(\.\./\.\./milestone#(https://github.com/guy-with-a-why/telemetry-blackbox/milestone#g' \
        -e 's#https://guy-with-a-why\.github\.io/telemetry-blackbox/flight#flight#g' \
        README.md > docs/introduction.md
    mkdir -p theme && cp docs/brand/favicon.svg theme/favicon.svg
    npm --prefix tools/flight ci --silent
    npm --prefix tools/flight run --silent build
    mdbook build
    if [[ -f target/coverage/coverage.json ]]; then cp target/coverage/coverage.json book/; fi

# Jot a timestamped note for tonight's blog post, e.g. just note "the board boots"
note +text:
    @mkdir -p ~/.local/state/telemetry-blackbox
    @printf '%s  %s\n' "$(date +%H:%M)" {{ quote(text) }} | tee -a ~/.local/state/telemetry-blackbox/notes-$(date +%F).log

# Lint and test the helper scripts and the flight strips
test-scripts:
    uvx ruff@0.14.0 check scripts
    uv run --no-project --with pytest==9.2.0 pytest -q scripts
    npm --prefix tools/flight ci --silent
    npm --prefix tools/flight run --silent typecheck
    npm --prefix tools/flight run --silent lint
    npm --prefix tools/flight test

# Check formatting, lints and licences for the crates, the firmware, bbcheck and the shell scripts
lint:
    shfmt --diff --indent 2 --case-indent scripts deploy
    shellcheck --external-sources $(shfmt --find scripts deploy)
    cargo fmt --all --check
    cargo clippy --workspace --all-targets --locked -- -D warnings
    cargo deny check bans licenses sources
    cd firmware && cargo fmt --check && cargo clippy --locked -- -D warnings
    cd firmware && cargo deny --target thumbv7em-none-eabihf check bans licenses sources
    uv run --locked --project tools/bbcheck ruff check tools/bbcheck

# Run the tests and build the firmware
test:
    cargo test --workspace --locked
    cd firmware && cargo build --locked
    cd tools/bbcheck && uv run --locked pytest

# Measure line coverage across Rust and bbcheck, and write the badge to
# target/coverage/coverage.json
coverage:
    mkdir -p target/coverage
    cargo llvm-cov --workspace --locked --json --summary-only --output-path target/coverage/rust.json
    cd tools/bbcheck && COVERAGE_FILE=../../target/coverage/.coverage uv run --locked pytest \
        --cov=bbcheck --cov-report=term --cov-report=json:../../target/coverage/python.json
    python3 scripts/coverage_badge.py target/coverage/rust.json target/coverage/python.json target/coverage/coverage.json

# Run the registry and caches the VMs use from the host
host:
    scripts/host.sh

# Create the five cluster VMs and start the host services; existing VMs are left alone
vms:
    scripts/vms.sh

# Check every VM is ready for kubeadm and pulls from the registry
vms-check:
    scripts/vms-check.sh

# Delete the five cluster VMs and their disks
[confirm("Delete all five VMs and their disks?")]
vms-delete:
    scripts/vms.sh delete

# Copy the kubeadm and kube-vip files, filled in, to the control planes
cluster-files:
    scripts/cluster-files.sh

# Bootstrap the cluster: kubeadm, kube-vip, the joins and Cilium. Safe to run again
cluster-up:
    scripts/cluster-up.sh

# Check the VIP, kube-vip, the nodes, etcd and Cilium
cluster-check:
    scripts/cluster-check.sh

# Snapshot etcd from a running control plane and copy it to the host
etcd-snapshot:
    scripts/etcd-snapshot.sh

# Deploy Redpanda on data-1's own disk and create its topics. Safe to run again
redpanda:
    scripts/redpanda.sh

# Check Redpanda keeps every record across a Pod restart, e.g. just redpanda-check 50000
redpanda-check records="10000":
    scripts/redpanda-check.sh {{ quote(records) }}

# Deploy ClickHouse on data-1's own disk, inside Redpanda's free-space floor, and apply its schema. Safe to run again
clickhouse:
    scripts/clickhouse.sh

# Insert frames twice and show the duplicates go at the merge, e.g. just clickhouse-check 50000
clickhouse-check frames="10000":
    scripts/clickhouse-check.sh {{ quote(frames) }}

# Build the VMs and the cluster from nothing, then check it
up: vms cluster-up cluster-check

# Deploy the echo workload, then watch the VIP, the API and echo through a drill
drill-watch:
    scripts/drill-watch.sh

# On my laptop: copy the kubeconfig and open the tunnel, e.g. just kubeconfig <home-server>
kubeconfig server:
    scripts/kubeconfig.sh {{ quote(server) }}

# Build the firmware and boot it on the simulated board; `quit` stops it
fly:
    cd firmware && cargo build --release --locked
    renode --console --disable-xwt renode/blackbox.resc
