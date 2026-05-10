var builder = WebApplication.CreateBuilder(args);

builder.Services
    .AddReverseProxy()
    .LoadFromConfig(builder.Configuration.GetSection("ReverseProxy"));

var app = builder.Build();

app.MapGet("/healthz", () => Results.Text("Healthy", "text/plain"));
app.MapReverseProxy();

await app.RunAsync().ConfigureAwait(false);
