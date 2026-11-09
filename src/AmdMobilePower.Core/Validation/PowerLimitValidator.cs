namespace AmdMobilePower.Core.Validation;

public static class PowerLimitValidator
{
    public const int MinimumWatts = 5;
    public const int MaximumWatts = 60;

    public static PowerLimitValidationResult Validate(int watts)
    {
        if (watts < MinimumWatts || watts > MaximumWatts)
        {
            return new PowerLimitValidationResult(
                false,
                watts,
                $"Power must be between {MinimumWatts}W and {MaximumWatts}W.");
        }

        return new PowerLimitValidationResult(true, watts, null);
    }
}

public readonly record struct PowerLimitValidationResult(
    bool IsValid,
    int Watts,
    string? Error);

