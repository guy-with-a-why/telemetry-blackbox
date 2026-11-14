# An apt cache for the VMs, so each package crosses the internet once.
FROM ubuntu:24.04@sha256:2198e4c65076e9cb0b3d695219df667c0e3b0072da64ca3c2648aca17dcecaf5

# ca-certificates lets it follow redirects to HTTPS, as pkgs.k8s.io does.
RUN apt-get update \
 && apt-get install -y --no-install-recommends apt-cacher-ng ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && chown apt-cacher-ng: /run/apt-cacher-ng

USER apt-cacher-ng
EXPOSE 3142
VOLUME /var/cache/apt-cacher-ng
CMD ["/usr/sbin/apt-cacher-ng", "ForeGround=1"]
