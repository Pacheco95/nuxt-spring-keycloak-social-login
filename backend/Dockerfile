# Multi-stage build: gradle build → fat jar → minimal JRE runtime.
# Gradle's wrapper handles the Spring Boot 4 + Kotlin 2.2 + JDK 24 toolchain.

FROM eclipse-temurin:24-jdk AS build
WORKDIR /app

# Cache deps before copying sources.
COPY gradlew settings.gradle.kts build.gradle.kts ./
COPY gradle ./gradle
RUN chmod +x ./gradlew && ./gradlew --no-daemon dependencies > /dev/null 2>&1 || true

COPY src ./src
RUN ./gradlew --no-daemon clean bootJar -x test

FROM eclipse-temurin:24-jre
WORKDIR /app
RUN useradd --system --uid 1001 --no-create-home spring
COPY --from=build /app/build/libs/*.jar /app/app.jar
USER spring
EXPOSE 8081
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
