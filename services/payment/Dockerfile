FROM eclipse-temurin:25-jdk-alpine AS builder
WORKDIR /src
COPY src/PaymentServer.java ./
RUN javac -d /bin-out PaymentServer.java

FROM gcr.io/distroless/java21-debian12:nonroot
USER 65532:65532
WORKDIR /app
COPY --from=builder /bin-out /app
EXPOSE 8083
ENTRYPOINT ["/usr/bin/java", "-cp", "/app", "services.payment.src.PaymentServer"]
