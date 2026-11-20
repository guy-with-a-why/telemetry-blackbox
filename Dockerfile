# One image per host crate: docker build --build-arg CRATE=gateway .
# CI builds each architecture on a native runner, so nothing cross-compiles.
# The base tag matches rust-toolchain.toml. That file stays out of the image,
# so rustup doesn't fetch the firmware target and lint tools here.
#
# cargo auditable embeds the crate list in the binary, so a scan of the image
# sees the Rust dependencies as well as the Debian packages (ADR 7).

FROM docker.io/library/rust:1.100.0-slim-trixie@sha256:e9d95b74296f7126a83ae3d041aeaba1ff4c478f13abc5cc034fcf7c131c3d4a AS build
RUN cargo install --locked cargo-auditable@0.7.7
ARG CRATE
WORKDIR /src
COPY Cargo.toml Cargo.lock ./
COPY gateway gateway
COPY pipeline pipeline
RUN test -n "$CRATE" && cargo auditable build --release --locked --package "$CRATE" \
    && cp "target/release/$CRATE" /app

FROM gcr.io/distroless/cc-debian13:nonroot@sha256:cb87acc574abe719b6e5c547384defa2f7b1f24af9605d3f618cf852495d8be2
COPY --from=build /app /app
ENTRYPOINT ["/app"]
