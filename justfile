set shell := ["bash", "-euo", "pipefail", "-c"]

d2_flags := "--layout=elk --theme=0 --dark-theme=200 --pad=24"

# List every recipe
default:
    @just --list

# Check every bench tool is installed
bench:
    @for tool in just d2 uv kubectl helm multipass docker renode cargo probe-rs clickhouse; do \
      if command -v "$tool" >/dev/null; then printf '%-10s ok\n' "$tool"; \
      else printf '%-10s missing\n' "$tool"; missing=1; fi; \
    done; exit "${missing:-0}"

# Render every diagram; files that declare steps are animated
diagrams:
    @for src in docs/diagrams/*.d2; do \
      extra=$(grep -q '^steps:' "$src" && echo --animate-interval=2000 || true); \
      d2 {{ d2_flags }} $extra "$src" "${src%.d2}.svg"; \
    done

# Scan the history for secrets, and files, commits and issues for blocked terms
audit:
    gitleaks git --no-banner --redact .
    scripts/blocked-terms.sh

# Build the docs site into book/: the README becomes its introduction, the
# flight strip and log come from the issues and the coverage badge from
# `just coverage`, if it has run
docs:
    sed -e 's#](docs/#](#g' -e 's#src="docs/#src="#g' -e 's#srcset="docs/#srcset="#g' \
        -e 's#(\.\./\.\./milestone#(https://github.com/guy-with-a-why/telemetry-blackbox/milestone#g' \
        README.md > docs/introduction.md
    mkdir -p theme && cp docs/brand/favicon.svg theme/favicon.svg
    python3 scripts/flight.py
    mdbook build
    if [[ -f target/coverage/coverage.json ]]; then cp target/coverage/coverage.json book/; fi

# Jot a timestamped note for tonight's blog post, e.g. just note "the board boots"
note +text:
    @mkdir -p ~/.local/state/telemetry-blackbox
    @printf '%s  %s\n' "$(date +%H:%M)" {{ quote(text) }} | tee -a ~/.local/state/telemetry-blackbox/notes-$(date +%F).log

# Lint and test the helper scripts
test-scripts:
    uvx ruff@0.14.0 check scripts
    uv run --no-project --with pytest==9.2.0 pytest -q scripts

# Check formatting and lints for the crates, the firmware, bbcheck and the shell scripts
lint:
    shfmt --diff --indent 2 --case-indent scripts deploy
    shellcheck --external-sources $(shfmt --find scripts deploy)
    cargo fmt --all --check
    cargo clippy --workspace --all-targets --locked -- -D warnings
    cd firmware && cargo fmt --check && cargo clippy --locked -- -D warnings
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

# Run the local image registry the VMs pull from
registry:
    scripts/registry.sh

# Create the five cluster VMs and start the registry; existing VMs are left alone
vms:
    scripts/vms.sh

# Delete the five cluster VMs and their disks
[confirm("Delete all five VMs and their disks?")]
vms-delete:
    scripts/vms.sh delete

# Build the firmware and boot it on the simulated board; `quit` stops it
fly:
    cd firmware && cargo build --release --locked
    renode --console --disable-xwt renode/blackbox.resc
