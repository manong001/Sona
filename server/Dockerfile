FROM maven:3.9.11-eclipse-temurin-17 AS build
WORKDIR /workspace
COPY pom.xml .
COPY src src
RUN mvn -B -DskipTests package

FROM eclipse-temurin:17-jre
WORKDIR /app
RUN mkdir -p /music /data && chown -R 10001:10001 /app /music /data
COPY --from=build --chown=10001:10001 /workspace/target/sona-server-*.jar /app/sona-server.jar
USER 10001:10001
EXPOSE 6699
ENTRYPOINT ["java", "-jar", "/app/sona-server.jar"]
