using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using StackExchange.Redis;
using Workbench.Application.Abstractions;
using Workbench.Infrastructure.Messaging;
using Workbench.Infrastructure.Persistence;
using Workbench.Infrastructure.Redis;

namespace Workbench.Infrastructure;

public static class InfrastructureServiceCollectionExtensions
{
    public static IServiceCollection AddWorkbenchPersistence(this IServiceCollection services, string connectionString)
    {
        services.AddDbContext<JobsDbContext>(o => o.UseNpgsql(connectionString));
        services.AddScoped<IJobRepository, EfJobRepository>();
        return services;
    }

    public static IServiceCollection AddWorkbenchRedis(this IServiceCollection services, string connectionString)
    {
        if (string.IsNullOrWhiteSpace(connectionString))
            throw new InvalidOperationException("Redis:ConnectionString (or env Redis__ConnectionString) is required.");

        services.AddSingleton<IConnectionMultiplexer>(_ => ConnectionMultiplexer.Connect(connectionString));
        services.AddSingleton<IWorkbenchJobMetrics, RedisWorkbenchJobMetrics>();
        services.AddSingleton<RedisPingHealthCheck>();
        return services;
    }

    public static IServiceCollection AddWorkbenchRabbitMqPublishOnly(
        this IServiceCollection services,
        string rabbitUri)
    {
        services.AddSingleton(new RabbitMqSettings(rabbitUri));
        services.AddSingleton<RabbitMqBus>();
        services.AddHostedService(sp => sp.GetRequiredService<RabbitMqBus>());
        services.AddScoped<IJobQueuePublisher, RabbitMqJobQueuePublisher>();
        return services;
    }

    public static IServiceCollection AddWorkbenchRabbitMqWorker(
        this IServiceCollection services,
        RabbitMqSettings settings)
    {
        services.AddSingleton(settings);
        services.AddSingleton<RabbitMqBus>();
        services.AddHostedService(sp => sp.GetRequiredService<RabbitMqBus>());
        services.AddHostedService<JobQueueConsumerHostedService>();
        services.AddScoped<IJobQueuePublisher, RabbitMqJobQueuePublisher>();
        return services;
    }
}
