# CortexTerminal.Relay — 文件传输与隧道的数据面服务（部署在大带宽服务器）
FROM --platform=$BUILDPLATFORM mcr.microsoft.com/dotnet/sdk:10.0 AS build
ARG TARGETARCH
ARG VERSION=0.0.0
WORKDIR /src
COPY src/Shared/CortexTerminal.Contracts/ ./src/Shared/CortexTerminal.Contracts/
COPY src/Relay/CortexTerminal.Relay/ ./src/Relay/CortexTerminal.Relay/
COPY CortexTerminal.sln Directory.Build.props ./
RUN dotnet publish src/Relay/CortexTerminal.Relay/CortexTerminal.Relay.csproj \
    -c Release -p:Version=${VERSION} -a $TARGETARCH -o /app/publish

FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
EXPOSE 8090
ENV ASPNETCORE_URLS=http://+:8090
ENV ASPNETCORE_ENVIRONMENT=Production
COPY --from=build /app/publish .
RUN useradd --system --create-home appuser && chown -R appuser:appuser /app
USER appuser
ENTRYPOINT ["dotnet", "corterm-relay.dll"]
