using AmdMobilePower.Core.Models;

namespace AmdMobilePower.Core.Validation;

public static class PowerLimitTargetValidator
{
    public static PowerLimitTargetValidationResult Validate(
        PowerLimitTarget target,
        PowerLimitCapability capability)
    {
        PowerLimitValidationResult stapm = PowerLimitValidator.Validate(target.StapmWatts);
        if (!stapm.IsValid)
        {
            return Invalid($"STAPM: {stapm.Error}");
        }

        PowerLimitValidationResult fast = PowerLimitValidator.Validate(target.FastWatts);
        if (!fast.IsValid)
        {
            return Invalid($"Fast: {fast.Error}");
        }

        PowerLimitValidationResult slow = PowerLimitValidator.Validate(target.SlowWatts);
        if (!slow.IsValid)
        {
            return Invalid($"Slow: {slow.Error}");
        }

        List<string> unsupported = new(3);
        if (!capability.SupportsStapm)
        {
            unsupported.Add("STAPM");
        }
        if (!capability.SupportsFast)
        {
            unsupported.Add("Fast");
        }
        if (!capability.SupportsSlow)
        {
            unsupported.Add("Slow");
        }

        if (unsupported.Count > 0)
        {
            return Invalid(
                $"The platform does not support these required power limits: {string.Join(", ", unsupported)}.");
        }

        return new PowerLimitTargetValidationResult(true, null);
    }

    private static PowerLimitTargetValidationResult Invalid(string error)
    {
        return new PowerLimitTargetValidationResult(false, error);
    }
}

public readonly record struct PowerLimitTargetValidationResult(bool IsValid, string? Error);
