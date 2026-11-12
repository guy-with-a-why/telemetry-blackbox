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
