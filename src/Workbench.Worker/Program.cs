using Workbench.Application;
using Workbench.Infrastructure;
using Workbench.Infrastructure.Messaging;

var builder = Host.CreateApplicationBuilder(args);

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

var host = builder.Build();
await host.RunAsync().ConfigureAwait(false);
