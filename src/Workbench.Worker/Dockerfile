# Build from repository root: docker build -f src/Workbench.Worker/Dockerfile src
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src
COPY Workbench.sln ./
COPY Workbench.Domain/Workbench.Domain.csproj Workbench.Domain/
COPY Workbench.Application/Workbench.Application.csproj Workbench.Application/
COPY Workbench.Infrastructure/Workbench.Infrastructure.csproj Workbench.Infrastructure/
COPY Workbench.Worker/Workbench.Worker.csproj Workbench.Worker/
RUN dotnet restore Workbench.Worker/Workbench.Worker.csproj
COPY . .
RUN dotnet publish Workbench.Worker/Workbench.Worker.csproj -c Release -o /app /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/aspnet:10.0-alpine AS runtime
WORKDIR /app
COPY --from=build /app .
ENV ASPNETCORE_URLS=http://+:8080
EXPOSE 8080
ENTRYPOINT ["dotnet", "Workbench.Worker.dll"]
