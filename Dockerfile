# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Build stage: Maven multi-module build on Java 8 (project: tech.powerjob 5.1.7)
# ---------------------------------------------------------------------------
FROM maven:3.8.6-openjdk-8-slim AS builder

WORKDIR /workspace

# The build context is the repository root: the parent POM and every module are needed.
COPY . .

# Install the parent POM only, then build every module (tests are run by CI, not by the image build).
RUN mvn -B clean install -N -DskipTests
RUN mvn -B clean package -DskipTests

# ---------------------------------------------------------------------------
# Runtime stage: PowerJob server (Spring Boot executable jar, repackaged by spring-boot-maven-plugin)
# ---------------------------------------------------------------------------
FROM eclipse-temurin:8-jdk

# Non-root user; its home holds PowerJob's data and logs (user.home/powerjob/...)
RUN groupadd --system --gid 10001 powerjob \
    && useradd --system --uid 10001 --gid powerjob --create-home --home-dir /home/powerjob --shell /usr/sbin/nologin powerjob

WORKDIR /app

COPY --from=builder /workspace/powerjob-server/powerjob-server-starter/target/*.jar app.jar
RUN chown powerjob:powerjob /app/app.jar \
    && mkdir -p /home/powerjob/powerjob \
    && chown -R powerjob:powerjob /home/powerjob

ENV JAVA_OPTS="-Xmx512m -Xms256m -XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Dfile.encoding=UTF-8 -Dsun.jnu.encoding=UTF-8 -Djava.security.egd=file:/dev/./urandom" \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    SPRING_PROFILES_ACTIVE=product \
    LOGGING_LEVEL_ROOT=INFO

# 7700: HTTP (web UI, OpenAPI, /actuator/health), 10086: AKKA, 10010: HTTP transporter, 10077: MU transporter
EXPOSE 7700 10086 10010 10077

VOLUME ["/home/powerjob/powerjob"]

USER powerjob:powerjob

# exec: java (not the shell) is the first process and receives the platform's SIGTERM for a graceful shutdown
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar /app/app.jar"]
