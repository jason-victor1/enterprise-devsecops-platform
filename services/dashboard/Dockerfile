FROM php:8.3-cli-alpine3.19
RUN addgroup -g 65532 -S nonroot && adduser -u 65532 -S nonroot -G nonroot
USER 65532:65532
WORKDIR /app
COPY index.php ./
EXPOSE 8086
ENTRYPOINT ["php", "-S", "0.0.0.0:8086", "index.php"]
