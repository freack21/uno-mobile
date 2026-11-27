# syntax=docker/dockerfile:1
# Last Card PWA: Flutter web build served by unprivileged nginx.
# Base images are build args so `setup.sh deploy --mirror` can switch to
# mirror.gcr.io when Docker Hub rate-limits the server.
ARG DEBIAN_IMAGE=debian:bookworm-slim
ARG NGINX_IMAGE=nginx:stable-alpine

FROM ${DEBIAN_IMAGE} AS build
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
RUN flutter pub get
COPY . .
RUN tool/build_web.sh /

FROM ${NGINX_IMAGE}
COPY deploy/nginx/nginx.conf /etc/nginx/nginx.conf
COPY --from=build /app/build/web /usr/share/nginx/html
USER nginx
EXPOSE 8080
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:8080/healthz >/dev/null || exit 1
