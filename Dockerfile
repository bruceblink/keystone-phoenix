ARG ELIXIR_VERSION=1.20.5
ARG OTP_VERSION=29
ARG IMAGE_REGISTRY=m.daocloud.io/docker.io/library/
ARG HEX_MIRROR=https://repo.hex.pm
ARG HEX_CACERTS_PATH=/etc/ssl/certs/ca-certificates.crt

FROM ${IMAGE_REGISTRY}elixir:${ELIXIR_VERSION}-otp-${OTP_VERSION} AS build

ARG HEX_MIRROR
ARG HEX_CACERTS_PATH

ENV MIX_ENV=prod \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HEX_MIRROR=${HEX_MIRROR} \
    HEX_CACERTS_PATH=${HEX_CACERTS_PATH}

RUN sed -i 's|http://deb.debian.org/|http://mirrors.tuna.tsinghua.edu.cn/|g' \
      /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends build-essential ca-certificates git openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY mix.exs mix.lock ./
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

FROM ${IMAGE_REGISTRY}debian:trixie-slim AS runtime

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    HOME=/app \
    PHX_SERVER=true \
    ELIXIR_ERL_OPTIONS=+fnu

RUN sed -i 's|http://deb.debian.org/|http://mirrors.tuna.tsinghua.edu.cn/|g' \
      /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl libstdc++6 openssl ncurses-bin netcat-openbsd \
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
  CMD ["curl", "--fail", "--silent", "--show-error", "http://127.0.0.1:4000/health/ready"]

EXPOSE 4000

ENTRYPOINT ["/app/bin/keystone_phoenix"]
CMD ["start"]
