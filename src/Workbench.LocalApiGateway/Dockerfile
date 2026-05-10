# Build from repository root: docker build -f src/Workbench.LocalApiGateway/Dockerfile src
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src
COPY Workbench.sln ./
COPY Workbench.LocalApiGateway/Workbench.LocalApiGateway.csproj Workbench.LocalApiGateway/
RUN dotnet restore Workbench.LocalApiGateway/Workbench.LocalApiGateway.csproj
COPY . .
RUN dotnet publish Workbench.LocalApiGateway/Workbench.LocalApiGateway.csproj -c Release -o /app /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS runtime
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Workbench.LocalApiGateway.dll"]
