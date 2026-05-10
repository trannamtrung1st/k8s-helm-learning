# Build from repository root: docker build -f src/Workbench.LocalGateway/Dockerfile src
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src
COPY Workbench.sln ./
COPY Workbench.LocalGateway/Workbench.LocalGateway.csproj Workbench.LocalGateway/
RUN dotnet restore Workbench.LocalGateway/Workbench.LocalGateway.csproj
COPY . .
RUN dotnet publish Workbench.LocalGateway/Workbench.LocalGateway.csproj -c Release -o /app /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS runtime
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Workbench.LocalGateway.dll"]
