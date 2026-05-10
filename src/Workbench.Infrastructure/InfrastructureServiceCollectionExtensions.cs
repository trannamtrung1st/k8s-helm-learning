using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Workbench.Application.Abstractions;
using Workbench.Infrastructure.Messaging;
using Workbench.Infrastructure.Persistence;

namespace Workbench.Infrastructure;

public static class InfrastructureServiceCollectionExtensions
{
    public static IServiceCollection AddWorkbenchPersistence(this IServiceCollection services, string connectionString)
    {
        services.AddDbContext<JobsDbContext>(o => o.UseNpgsql(connectionString));
        services.AddScoped<IJobRepository, EfJobRepository>();
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
