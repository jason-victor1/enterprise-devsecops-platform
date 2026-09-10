FROM ruby:3.3-alpine3.19
RUN addgroup -g 65532 -S nonroot && adduser -u 65532 -S nonroot -G nonroot
USER 65532:65532
WORKDIR /app
COPY server.rb ./
EXPOSE 8084
ENTRYPOINT ["ruby", "server.rb"]
