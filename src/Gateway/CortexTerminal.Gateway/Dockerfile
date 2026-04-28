# ===== Stage 1: Build Frontend =====
FROM node:22-slim AS frontend
RUN corepack enable && corepack prepare pnpm@10 --activate
WORKDIR /build
COPY src/Gateway/CortexTerminal.Console/package.json src/Gateway/CortexTerminal.Console/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile
COPY src/Gateway/CortexTerminal.Console/ ./
RUN pnpm build --outDir /build/dist

# ===== Stage 2: Build .NET =====
FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY src/Shared/CortexTerminal.Contracts/ ./src/Shared/CortexTerminal.Contracts/
COPY src/Gateway/CortexTerminal.Gateway/ ./src/Gateway/CortexTerminal.Gateway/
COPY CortexTerminal.sln Directory.Build.props ./
COPY --from=frontend /build/dist ./src/Gateway/CortexTerminal.Gateway/wwwroot/
RUN dotnet publish src/Gateway/CortexTerminal.Gateway/CortexTerminal.Gateway.csproj \
    -c Release -o /app/publish

# ===== Stage 3: Runtime =====
FROM mcr.microsoft.com/dotnet/aspnet:10.0 AS runtime
WORKDIR /app
EXPOSE 5045
ENV ASPNETCORE_URLS=http://+:5045
ENV ASPNETCORE_ENVIRONMENT=Production
COPY --from=build /app/publish .
RUN useradd --system --create-home appuser && chown -R appuser:appuser /app
USER appuser
ENTRYPOINT ["dotnet", "CortexTerminal.Gateway.dll"]
