set shell := ["bash", "-euo", "pipefail", "-c"]

d2_flags := "--layout=elk --theme=0 --dark-theme=200 --pad=24"

# List every recipe
default:
    @just --list

# Check every bench tool is installed
bench:
    @for tool in just d2 uv kubectl helm multipass renode cargo; do \
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

# Build the docs site into book/: the README becomes its introduction, and
# the flight strip and log come from the issues
docs:
    sed -e 's#](docs/#](#g' -e 's#src="docs/#src="#g' -e 's#srcset="docs/#srcset="#g' \
        -e 's#(\.\./\.\./milestone#(https://github.com/guy-with-a-why/telemetry-blackbox/milestone#g' \
        README.md > docs/introduction.md
    mkdir -p theme && cp docs/brand/favicon.svg theme/favicon.svg
    python3 scripts/flight.py
    mdbook build

# Lint and test the helper scripts
test-scripts:
    uvx ruff@0.14.0 check scripts
    uv run --no-project --with pytest==8.4.2 pytest -q scripts
