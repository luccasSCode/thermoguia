# Contexto de build: raiz do repositório (precisa de packages/thermo_core).
FROM dart:stable AS build
WORKDIR /src
COPY packages/thermo_core packages/thermo_core
COPY backend/pubspec.yaml backend/
WORKDIR /src/backend
RUN dart pub get
COPY backend/ .
RUN dart pub get --offline && dart compile exe bin/server.dart -o /server

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=build /server /app/server
ENV CACHE_DIR=/app/cache
VOLUME ["/app/cache"]
EXPOSE 8080
CMD ["/app/server"]
