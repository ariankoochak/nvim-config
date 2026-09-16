# Base image for the installer scenarios.
#
# Deliberately bare: curl, ca-certificates and sudo, which is what the README
# claims a clean machine needs. Everything else has to come from the installer.
# Node is added from the official tarball because the installer must never
# install Node itself -- these tests check that it *finds* one.
FROM ubuntu:24.04

ARG NODE_VERSION=22.11.0
ARG DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends curl ca-certificates sudo xz-utils locales \
 && locale-gen en_US.UTF-8 \
 && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in amd64) n_arch=x64 ;; arm64) n_arch=arm64 ;; *) echo "unsupported $arch" >&2; exit 1 ;; esac; \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${n_arch}.tar.xz" -o /tmp/node.tar.xz; \
    mkdir -p /opt/node; \
    tar -xJf /tmp/node.tar.xz -C /opt/node --strip-components=1; \
    rm /tmp/node.tar.xz
ENV PATH=/opt/node/bin:$PATH

RUN useradd --create-home --shell /bin/bash tester \
 && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester \
 && chmod 0440 /etc/sudoers.d/tester

USER tester
WORKDIR /home/tester

# A real .bashrc, so the ensure_line/no-duplicates behaviour is exercised.
RUN printf '# test bashrc\nexport PS1="$ "\n' > /home/tester/.bashrc

COPY --chown=tester:tester . /home/tester/nvim-config
