# Build from repository root: docker build -f src/Workbench.Jobs/Dockerfile src
FROM mcr.microsoft.com/dotnet/sdk:10.0-alpine AS build
WORKDIR /src
COPY Workbench.sln ./
COPY Workbench.Domain/Workbench.Domain.csproj Workbench.Domain/
COPY Workbench.Application/Workbench.Application.csproj Workbench.Application/
COPY Workbench.Infrastructure/Workbench.Infrastructure.csproj Workbench.Infrastructure/
COPY Workbench.Jobs/Workbench.Jobs.csproj Workbench.Jobs/
RUN dotnet restore Workbench.Jobs/Workbench.Jobs.csproj
COPY . .
RUN dotnet publish Workbench.Jobs/Workbench.Jobs.csproj -c Release -o /app /p:UseAppHost=false

FROM mcr.microsoft.com/dotnet/runtime:10.0-alpine AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "Workbench.Jobs.dll"]
