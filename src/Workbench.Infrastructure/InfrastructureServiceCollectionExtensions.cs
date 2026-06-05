using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;
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

    public static IServiceCollection AddWorkbenchRedis(this IServiceCollection services, IConfiguration configuration)
    {
        services.Configure<RedisOptions>(configuration.GetSection(RedisOptions.SectionName));
        services.AddSingleton<IConnectionMultiplexer>(sp =>
            ConnectionMultiplexer.Connect(
                sp.GetRequiredService<IOptions<RedisOptions>>().Value.ToConfigurationOptions()));
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
        services.AddSingleton<RabbitMqBusHealthCheck>();
        services.AddHostedService(sp => sp.GetRequiredService<RabbitMqBus>());
        services.AddHostedService<JobQueueConsumerHostedService>();
        services.AddScoped<IJobQueuePublisher, RabbitMqJobQueuePublisher>();
        return services;
    }
}
