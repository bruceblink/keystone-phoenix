# syntax=docker/dockerfile:1.10

ARG ELIXIR_VERSION=1.20.5
ARG OTP_VERSION=29
ARG IMAGE_REGISTRY=
ARG HEX_MIRROR=https://repo.hex.pm
ARG HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt
# 发布环境可以显式切换 Debian 软件源，默认使用 Debian 官方源。
ARG DEBIAN_MIRROR=http://deb.debian.org
ARG ELIXIR_IMAGE_DIGEST=sha256:1b850191faeaae55678b782cd8b34d391f793672f3175b1956d024f794ca321b
ARG DEBIAN_IMAGE_DIGEST=sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2

FROM ${IMAGE_REGISTRY}elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION}@${ELIXIR_IMAGE_DIGEST} AS build

ARG HEX_MIRROR
ARG HEX_CACERTS_PATH
ARG DEBIAN_MIRROR

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HEX_MIRROR=${HEX_MIRROR} \
    HEX_CACERTS_PATH=${HEX_CACERTS_PATH}

# The managed development environment routes HTTPS through a local proxy whose
# CA is not part of the public Debian trust store. BuildKit callers can provide
# that CA with `--secret id=proxy_ca,src=/path/to/ca.crt`; the secret is used
# only in this build stage and is never copied into the runtime image. CI builds
# that do not need a proxy continue to use the standard CA bundle.
RUN --mount=type=secret,id=proxy_ca,target=/run/secrets/proxy_ca,required=false \
    sed -i "s|http://deb.debian.org/|${DEBIAN_MIRROR}/|g" \
      /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates git libsctp1 openssl \
    && if [ -f /run/secrets/proxy_ca ]; then \
      cp /run/secrets/proxy_ca /usr/local/share/ca-certificates/build-proxy-ca.crt \
      && update-ca-certificates; \
    fi \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY mix.exs mix.lock ./
COPY vendor/xlsxir vendor/xlsxir
RUN mix local.hex --force \
    && mix local.rebar --force \
    && mix deps.get --only prod \
    && mix deps.compile

COPY config config
COPY lib lib
COPY priv priv
COPY rel rel

RUN mix compile --warnings-as-errors \
    && mix release

FROM ${IMAGE_REGISTRY}debian:trixie-slim@${DEBIAN_IMAGE_DIGEST} AS runtime

ARG DEBIAN_MIRROR

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/app \
    PHX_SERVER=true \
    ELIXIR_ERL_OPTIONS=+fnu

RUN sed -i "s|http://deb.debian.org/|${DEBIAN_MIRROR}/|g" \
      /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends adduser ca-certificates curl libsctp1 libstdc++6 openssl ncurses-bin \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/_build/prod/rel/keystone_phoenix ./

RUN addgroup --system keystone \
    && adduser --system --ingroup keystone --home /app keystone \
    && mkdir -p /var/lib/keystone/resources \
    && chown -R keystone:keystone /app /var/lib/keystone

VOLUME ["/var/lib/keystone/resources"]

USER keystone

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD ["curl", "--fail", "--silent", "--show-error", "http://127.0.0.1:4000/api/v1/health/ready"]

EXPOSE 4000

ENTRYPOINT ["/app/bin/keystone_phoenix"]
CMD ["start"]
