# API en C# / .NET. Ajusta la version (8.0 / 9.0 / 10.0) a la de tu proyecto.
# Build:  docker build -t miapi --build-arg PROJECT=src/MiApi/MiApi.csproj --build-arg APP_DLL=MiApi.dll .
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
ARG PROJECT
WORKDIR /src
COPY . .
RUN dotnet publish "$PROJECT" -c Release -o /out

FROM mcr.microsoft.com/dotnet/aspnet:8.0
ARG APP_DLL
ENV APP_DLL=$APP_DLL \
    ASPNETCORE_URLS=http://+:8080
WORKDIR /app
COPY --from=build /out .
USER app
EXPOSE 8080
ENTRYPOINT ["sh", "-c", "exec dotnet \"$APP_DLL\""]
