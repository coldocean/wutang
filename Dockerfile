# WU-tang — Eggdrop IRC bot for the Wunderbar network.
# Compiles Eggdrop 1.9.5 from source (latest stable) with TLS support.
#
# Build:  docker build -t wutang .
# Run:    docker run -d --name wutang wutang
#
FROM debian:trixie-slim AS build

LABEL org.opencontainers.image.title="WU-tang Eggdrop Bot" \
      org.opencontainers.image.description="Eggdrop 1.9.5 IRC bot for the Wunderbar network" \
      org.opencontainers.image.source="https://github.com/coldocean/wutang"

ENV DEBIAN_FRONTEND=noninteractive
ENV EGGDROP_VERSION=1.9.5

# Build toolchain + Tcl + OpenSSL headers.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential tcl tcl-dev libssl-dev zlib1g-dev \
      ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/build
# Fetch and compile Eggdrop into /opt/eggdrop.
RUN curl -fsSL "https://ftp.eggheads.org/pub/eggdrop/source/1.9/eggdrop-${EGGDROP_VERSION}.tar.gz" -o eggdrop.tar.gz \
 && tar xzf eggdrop.tar.gz \
 && cd eggdrop-${EGGDROP_VERSION} \
 && ./configure --prefix=/opt/eggdrop \
 && make config \
 && make -j"$(nproc)" \
 && make install \
 && cd / && rm -rf /tmp/build

# ---- Runtime image ----
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
# Cache-bust token — bump to force the runtime layers to rebuild.
ARG RUNTIME_CACHEBUST=2
RUN echo "cachebust ${RUNTIME_CACHEBUST}" \
 && apt-get update \
 && apt-get install -y --no-install-recommends tcl libssl3 zlib1g ca-certificates gosu \
 && rm -rf /var/lib/apt/lists/* \
 && useradd -m -d /opt/eggdrop -s /usr/sbin/nologin eggdrop || true

# Copy the compiled bot from the build stage.
COPY --from=build /opt/eggdrop /opt/eggdrop

# Bot config + entrypoint. Our custom TCL goes into scripts/wunderbar/ so it
# does NOT clobber Eggdrop's stock scripts (alltools.tcl, etc.) in scripts/.
COPY config/eggdrop.conf /opt/eggdrop/eggdrop.conf
COPY config/telnet-banner.txt /opt/eggdrop/telnet-banner.txt
COPY scripts/ /opt/eggdrop/scripts/wunderbar/
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
 && mkdir -p /opt/eggdrop/logs /opt/eggdrop/data \
 && chown -R eggdrop:eggdrop /opt/eggdrop

WORKDIR /opt/eggdrop
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
