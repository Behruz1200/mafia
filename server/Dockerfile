# Build from the repo root:  docker build -f server/Dockerfile -t mafia-server .
FROM dart:3.14 AS build
WORKDIR /src

# The pub workspace also lists the Flutter app, which needs the Flutter SDK.
# The server does not, so drop the app from the workspace inside the image.
COPY pubspec.yaml ./
RUN sed -i '/^  - app$/d' pubspec.yaml
COPY packages/contracts/pubspec.yaml packages/contracts/
COPY packages/mafia_engine/pubspec.yaml packages/mafia_engine/
COPY server/pubspec.yaml server/
RUN dart pub get

COPY packages packages
COPY server server
RUN dart pub get --offline && dart compile exe server/bin/server.dart -o /server

FROM scratch
COPY --from=build /runtime/ /
COPY --from=build /server /app/server
COPY server/migrations /app/migrations
EXPOSE 8080
CMD ["/app/server"]
