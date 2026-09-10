FROM gcr.io/distroless/python3-debian12:nonroot
USER 65532:65532
WORKDIR /app
COPY server.py ./
EXPOSE 8085
ENTRYPOINT ["/usr/bin/python3", "server.py"]
