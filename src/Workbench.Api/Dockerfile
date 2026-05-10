# Build from repository root: docker build -f src/Workbench.Api/Dockerfile src
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src
COPY Workbench.sln ./
COPY Workbench.Domain/Workbench.Domain.csproj Workbench.Domain/
COPY Workbench.Application/Workbench.Application.csproj Workbench.Application/
COPY Workbench.Infrastructure/Workbench.Infrastructure.csproj Workbench.Infrastructure/
COPY Workbench.Api/Workbench.Api.csproj Workbench.Api/
RUN dotnet restore Workbench.Api/Workbench.Api.csproj
COPY . .
RUN dotnet publish Workbench.Api/Workbench.Api.csproj -c Release -o /app /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS runtime
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Workbench.Api.dll"]
