using StackExchange.Redis;

namespace Workbench.Infrastructure.Redis;

/// <summary>
/// Redis client settings. <see cref="ConnectionString"/> overrides structured fields when set
/// (e.g. <c>Redis__ConnectionString</c> from cluster secrets). Otherwise builds a
/// StackExchange.Redis configuration from <see cref="Endpoints"/>, credentials, and
/// <see cref="Cluster.Enabled"/>.
/// </summary>
public sealed class RedisOptions
{
    public const string SectionName = "Redis";

    /// <summary>Full StackExchange.Redis connection string; takes precedence when non-empty.</summary>
    public string? ConnectionString { get; set; }

    /// <summary>Seed endpoints as <c>host:port</c>. Use multiple entries when cluster mode is enabled.</summary>
    public string[] Endpoints { get; set; } = ["localhost:6379"];

    public string? User { get; set; }

    public string? Password { get; set; }

    public RedisClusterOptions Cluster { get; set; } = new();

    public ConfigurationOptions ToConfigurationOptions()
    {
        if (!string.IsNullOrWhiteSpace(ConnectionString))
            return ConfigurationOptions.Parse(ConnectionString.Trim());

        if (Endpoints is not { Length: > 0 } endpoints)
            throw new InvalidOperationException(
                "Redis:Endpoints (or env Redis__Endpoints__*) is required when Redis:ConnectionString is not set.");

        if (Cluster.Enabled && endpoints.Length < 2)
            throw new InvalidOperationException(
                "Redis:Cluster:Enabled requires at least two seed endpoints in Redis:Endpoints.");

        var options = new ConfigurationOptions
        {
            AbortOnConnectFail = false,
        };

        foreach (var endpoint in endpoints)
        {
            if (string.IsNullOrWhiteSpace(endpoint))
                continue;
            options.EndPoints.Add(endpoint.Trim());
        }

        if (options.EndPoints.Count == 0)
            throw new InvalidOperationException("Redis:Endpoints must include at least one host:port.");

        if (!string.IsNullOrWhiteSpace(User))
            options.User = User;
        if (!string.IsNullOrWhiteSpace(Password))
            options.Password = Password;

        return options;
    }
}

public sealed class RedisClusterOptions
{
    public bool Enabled { get; set; }
}
