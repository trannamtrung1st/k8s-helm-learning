using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using Workbench.Application;
using Workbench.Infrastructure;
using Workbench.Infrastructure.Messaging;
using Workbench.Infrastructure.Redis;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<WorkbenchOptions>(
    builder.Configuration.GetSection(WorkbenchOptions.SectionName));

var cs = builder.Configuration.GetConnectionString("Default")
    ?? throw new InvalidOperationException("ConnectionStrings:Default is required");

var rabbitUri = builder.Configuration["RabbitMq:Uri"]
    ?? throw new InvalidOperationException("RabbitMq:Uri is required");

var consumerConcurrency = builder.Configuration.GetValue("RabbitMq:ConsumerConcurrency", 4);
var prefetchPerConsumer = builder.Configuration.GetValue("RabbitMq:PrefetchPerConsumer", 10);
var rabbitSettings = new RabbitMqSettings(rabbitUri, consumerConcurrency, prefetchPerConsumer);

builder.Services.AddWorkbenchPersistence(cs);
builder.Services.AddWorkbenchApplicationServices();
builder.Services.AddWorkbenchRabbitMqWorker(rabbitSettings);
builder.Services.AddWorkbenchRedis(builder.Configuration);

builder.Services.AddHealthChecks()
    .AddNpgSql(cs, tags: ["ready"])
    .AddCheck<RabbitMqBusHealthCheck>("rabbitmq", tags: ["live", "ready"])
    .AddCheck<RedisPingHealthCheck>("redis", tags: ["ready"]);

var app = builder.Build();

var livePredicate = new Func<HealthCheckRegistration, bool>(r => r.Tags.Contains("live"));
var readyPredicate = new Func<HealthCheckRegistration, bool>(r => r.Tags.Contains("ready"));

app.MapHealthChecks("/healthz", new HealthCheckOptions { Predicate = livePredicate });
app.MapHealthChecks("/ready", new HealthCheckOptions { Predicate = readyPredicate });

await app.RunAsync().ConfigureAwait(false);
