using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using RabbitMQ.Client;
using Workbench.Application;
using Workbench.Application.Abstractions;
using Workbench.Domain;
using Workbench.Infrastructure;
using Workbench.Infrastructure.Persistence;
using Workbench.Infrastructure.Redis;

var builder = WebApplication.CreateBuilder(args);

builder.Services.Configure<WorkbenchOptions>(
    builder.Configuration.GetSection(WorkbenchOptions.SectionName));

builder.Services.AddWorkbenchApplicationServices();

builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
        policy.AllowAnyOrigin().AllowAnyHeader().AllowAnyMethod());
});

builder.Services.ConfigureHttpJsonOptions(o =>
{
    o.SerializerOptions.DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull;
    o.SerializerOptions.PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase;
});

var connectionString = builder.Configuration.GetConnectionString("Default")
    ?? throw new InvalidOperationException("ConnectionStrings:Default is required");

var rabbitUri = builder.Configuration["RabbitMq:Uri"]
    ?? throw new InvalidOperationException("RabbitMq:Uri is required");

var redisConnectionString = builder.Configuration["Redis:ConnectionString"]
    ?? throw new InvalidOperationException("Redis:ConnectionString is required");

builder.Services.AddWorkbenchPersistence(connectionString);
builder.Services.AddWorkbenchRabbitMqPublishOnly(rabbitUri);
builder.Services.AddWorkbenchRedis(redisConnectionString);

builder.Services.AddHealthChecks()
    .AddCheck("live", () => HealthCheckResult.Healthy(), tags: ["live"])
    .AddNpgSql(connectionString, tags: ["ready"])
    .AddAsyncCheck("rabbitmq", async () =>
    {
        var factory = new ConnectionFactory { Uri = new Uri(rabbitUri) };
        await using var conn = await factory.CreateConnectionAsync().ConfigureAwait(false);
        return HealthCheckResult.Healthy();
    }, tags: ["ready"])
    .AddCheck<RedisPingHealthCheck>("redis", tags: ["ready"]);

builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(o =>
{
    o.SwaggerDoc("v1", new Microsoft.OpenApi.OpenApiInfo
    {
        Title = "Workbench API",
        Version = "v1",
        Description =
            "Synthetic load jobs: enqueue, list, get, sync workloads, and Redis-backed counters (GET /v1/metrics).",
    });
});

var app = builder.Build();

app.UseCors();

app.UseSwagger();
app.UseSwaggerUI(o =>
{
    o.RoutePrefix = "swagger";
    o.SwaggerEndpoint("/swagger/v1/swagger.json", "Workbench API v1");
});

var livePredicate = new Func<HealthCheckRegistration, bool>(r => r.Tags.Contains("live"));
var readyPredicate = new Func<HealthCheckRegistration, bool>(r => r.Tags.Contains("ready"));

app.MapHealthChecks("/healthz", new HealthCheckOptions { Predicate = livePredicate });
app.MapHealthChecks("/ready", new HealthCheckOptions { Predicate = readyPredicate });

using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<JobsDbContext>();
    await db.Database.MigrateAsync();
}

var jobsApi = app.MapGroup("/v1");

jobsApi.MapPost("/jobs", async (JobPayload body, IJobsApplicationService jobs, CancellationToken ct) =>
{
    var result = await jobs.EnqueueJobAsync(body, ct).ConfigureAwait(false);
    return result switch
    {
        EnqueueJobSuccess s => Results.Created($"/v1/jobs/{s.Id:D}", new { id = s.Id, status = s.Status }),
        EnqueueJobValidationFailed v => ValidationFailed(v.Errors),
        _ => Results.Problem(),
    };
}).WithName("CreateJob");

jobsApi.MapGet("/jobs/{id:guid}", async (Guid id, IJobsApplicationService jobs, CancellationToken ct) =>
{
    var job = await jobs.GetJobAsync(id, ct).ConfigureAwait(false);
    return job is null ? Results.NotFound() : Results.Ok(ToAnonymous(job));
}).WithName("GetJobById");

jobsApi.MapGet("/jobs", async (int? limit, IJobsApplicationService jobs, CancellationToken ct) =>
{
    var list = await jobs.ListJobsAsync(limit ?? 20, ct).ConfigureAwait(false);
    return Results.Ok(list.Select(ToAnonymous).ToArray());
}).WithName("ListJobs");

jobsApi.MapGet("/metrics", async (IWorkbenchJobMetrics metrics, CancellationToken ct) =>
{
    var enqueued = await metrics.GetEnqueueTotalAsync(ct).ConfigureAwait(false);
    var processed = await metrics.GetProcessedTotalAsync(ct).ConfigureAwait(false);
    return Results.Ok(new { jobsEnqueuedTotal = enqueued, jobsProcessedTotal = processed });
}).WithName("JobMetrics");

jobsApi.MapPost("/work", async (JobPayload body, IJobsApplicationService jobs, CancellationToken ct) =>
{
    var result = await jobs.RunSyncWorkAsync(body, ct).ConfigureAwait(false);
    return result switch
    {
        SyncWorkSuccess s =>
            Results.Ok(new
            {
                mode = "sync",
                elapsedMs = s.Metrics.WallClockMs,
                peakWorkingSetBytes = s.Metrics.PeakWorkingSetBytes,
                processAvgCpuPercent = s.Metrics.ProcessAvgCpuPercent,
            }),
        SyncWorkValidationFailed v => ValidationFailed(v.Errors),
        _ => Results.Problem(),
    };
}).WithName("SyncWork");

app.Run();

static IResult ValidationFailed(IReadOnlyList<JobPayloadValidation.ValidationError> errors)
{
    var details = errors.ToDictionary(e => ToCamel(e.Field), e => e.Message);
    return Results.Json(new { error = "validation_failed", details }, statusCode: 400);
}

static string ToCamel(string name) =>
    string.IsNullOrEmpty(name) ? name : char.ToLowerInvariant(name[0]) + name[1..];

static object ToAnonymous(JobDetailDto j) => new
{
    id = j.Id,
    status = j.Status,
    payload = j.Payload,
    createdAt = j.CreatedAt,
    startedAt = j.StartedAt,
    finishedAt = j.FinishedAt,
    error = j.Error,
    executionDurationMs = j.ExecutionDurationMs,
    peakWorkingSetBytes = j.PeakWorkingSetBytes,
    processAvgCpuPercent = j.ProcessAvgCpuPercent,
};
