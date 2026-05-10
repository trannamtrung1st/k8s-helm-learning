using Microsoft.Extensions.DependencyInjection;
using Workbench.Application.Abstractions;

namespace Workbench.Application;

public static class ApplicationServiceCollectionExtensions
{
    public static IServiceCollection AddWorkbenchApplicationServices(this IServiceCollection services)
    {
        services.AddScoped<IJobsApplicationService, JobsApplicationService>();
        services.AddScoped<IQueuedJobExecutor, QueuedJobExecutor>();
        return services;
    }
}
