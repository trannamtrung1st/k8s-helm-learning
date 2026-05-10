using System.Text.Json;
using System.Text.Json.Serialization;

namespace Workbench.Infrastructure.Messaging;

internal static class JobEnvelopeJson
{
    internal static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };
}
