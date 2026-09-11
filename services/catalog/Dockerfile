FROM golang:1.23.4-alpine3.19 AS builder
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY main.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-w -s -extldflags '-static'" -o /bin/catalog main.go

FROM gcr.io/distroless/static-debian12:nonroot
USER 65532:65532
WORKDIR /app
COPY --from=builder /bin/catalog /app/catalog
EXPOSE 8080
ENTRYPOINT ["/app/catalog"]
