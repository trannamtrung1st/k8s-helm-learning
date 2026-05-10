namespace Workbench.Domain;

public static class JobPayloadValidation
{
    public sealed class ValidationError(string field, string message)
    {
        public string Field { get; } = field;
        public string Message { get; } = message;
    }

    public static IReadOnlyList<ValidationError> Validate(JobPayload payload, WorkbenchLimits limits)
    {
        List<ValidationError>? errors = null;

        void Add(string field, string message)
        {
            errors ??= [];
            errors.Add(new ValidationError(field, message));
        }

        if (payload.DurationSec < limits.DurationSecMin || payload.DurationSec > limits.DurationSecMax)
            Add(nameof(payload.DurationSec), $"must be between {limits.DurationSecMin} and {limits.DurationSecMax}");

        if (payload.CpuPercent < limits.CpuPercentMin || payload.CpuPercent > limits.CpuPercentMax)
            Add(nameof(payload.CpuPercent), $"must be between {limits.CpuPercentMin} and {limits.CpuPercentMax}");

        if (payload.MemoryMb < limits.MemoryMbMin || payload.MemoryMb > limits.MemoryMbMax)
            Add(nameof(payload.MemoryMb), $"must be between {limits.MemoryMbMin} and {limits.MemoryMbMax}");

        return errors ?? (IReadOnlyList<ValidationError>)Array.Empty<ValidationError>();
    }
}
