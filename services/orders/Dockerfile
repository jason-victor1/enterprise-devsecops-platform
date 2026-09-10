FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine3.19 AS builder
WORKDIR /src
COPY Orders.csproj ./
RUN dotnet restore
COPY Program.cs ./
RUN dotnet publish -c Release --no-restore -o /app/publish /p:PublishSingleFile=false

FROM mcr.microsoft.com/dotnet/aspnet:8.0-alpine3.19
RUN addgroup -g 65532 -S nonroot && adduser -u 65532 -S nonroot -G nonroot
USER 65532:65532
WORKDIR /app
COPY --from=builder --chown=65532:65532 /app/publish ./
ENV ASPNETCORE_URLS=http://+:8082
ENV DOTNET_EnableDiagnostics=0
EXPOSE 8082
ENTRYPOINT ["dotnet", "Orders.dll"]
