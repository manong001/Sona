FROM maven:3.9.11-eclipse-temurin-17 AS build
WORKDIR /workspace
COPY pom.xml .
RUN --mount=type=cache,target=/root/.m2,sharing=locked \
    mvn -B -DskipTests dependency:go-offline
COPY src src
RUN --mount=type=cache,target=/root/.m2,sharing=locked \
    mvn -B -DskipTests package

FROM eclipse-temurin:17-jre
WORKDIR /app
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /music /data && chown -R 10001:10001 /app /music /data
COPY --from=build --chown=10001:10001 /workspace/target/sona-server-*.jar /app/sona-server.jar
USER 10001:10001
EXPOSE 6699
ENTRYPOINT ["java", "-jar", "/app/sona-server.jar"]
