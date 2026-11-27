# syntax=docker/dockerfile:1
# Last Card: the PWA (target "web", the default: Flutter web build served by
# unprivileged nginx) and the multiplayer server (target "server").
# Base images are build args so `setup.sh deploy --mirror` can switch to
# mirror.gcr.io when Docker Hub rate-limits the server.
ARG DEBIAN_IMAGE=debian:bookworm-slim
ARG NGINX_IMAGE=nginx:stable-alpine

FROM ${DEBIAN_IMAGE} AS sdk
ARG FLUTTER_VERSION=3.50.1
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
# Pinned SDK; must satisfy the Dart constraint in pubspec.yaml.
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" https://github.com/flutter/flutter.git /opt/flutter
ENV PATH=/opt/flutter/bin:$PATH \
    CI=true \
    FLUTTER_SUPPRESS_ANALYTICS=true
RUN flutter config --no-analytics --no-cli-animations >/dev/null \
 && flutter precache --web --no-android --no-ios
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
COPY packages ./packages
RUN flutter pub get
COPY server/pubspec.yaml server/pubspec.lock ./server/
RUN cd server && dart pub get
COPY . .

FROM sdk AS server-build
RUN mkdir -p /out && cd server && dart compile exe bin/server.dart -o /out/server

FROM ${DEBIAN_IMAGE} AS server
# /data holds rooms.json so rooms survive restarts (mount a volume there).
RUN useradd --system --uid 10001 --no-create-home lastcard \
 && mkdir -p /data && chown lastcard:lastcard /data
COPY --from=server-build /out/server /app/server
USER lastcard
ENV PORT=8081 \
    LC_DATA_DIR=/data
EXPOSE 8081
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD ["/app/server", "--healthcheck"]
ENTRYPOINT ["/app/server"]

FROM sdk AS build
RUN tool/build_web.sh /

FROM ${NGINX_IMAGE} AS web
COPY deploy/nginx/nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/build/web /usr/share/nginx/html
USER nginx
EXPOSE 8080
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1
