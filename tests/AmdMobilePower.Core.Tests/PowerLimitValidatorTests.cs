using AmdMobilePower.Core.Models;
using AmdMobilePower.Core.Validation;

namespace AmdMobilePower.Core.Tests;

public sealed class PowerLimitValidatorTests
{
    [Fact]
    public void TargetValidate_RejectsNullCapability()
    {
        Assert.Throws<ArgumentNullException>(() =>
            PowerLimitTargetValidator.Validate(
                PowerLimitTarget.Uniform(25),
                null!));
    }

    [Theory]
    [InlineData(5, true)]
    [InlineData(25, true)]
    [InlineData(60, true)]
    [InlineData(4, false)]
    [InlineData(61, false)]
    public void Validate_EnforcesInitialSupportedRange(int watts, bool expected)
    {
        PowerLimitValidationResult result = PowerLimitValidator.Validate(watts);

        Assert.Equal(expected, result.IsValid);
        Assert.Equal(watts, result.Watts);
    }

    [Fact]
    public void TargetValidate_RejectsUnsupportedLimitBeforeHardwareWrite()
    {
        PowerLimitTargetValidationResult result = PowerLimitTargetValidator.Validate(
            PowerLimitTarget.Uniform(25),
            new PowerLimitCapability(
                SupportsStapm: true,
                SupportsFast: true,
                SupportsSlow: false));

        Assert.False(result.IsValid);
        Assert.Contains("Slow", result.Error);
    }

    [Fact]
    public void TargetValidate_AllowsMissingStapmWhenFastAndSlowAreSupported()
    {
        PowerLimitTargetValidationResult result = PowerLimitTargetValidator.Validate(
            PowerLimitTarget.Uniform(25),
            new PowerLimitCapability(
                SupportsStapm: false,
                SupportsFast: true,
                SupportsSlow: true));

        Assert.True(result.IsValid);
        Assert.Null(result.Error);
    }

    [Fact]
    public void TargetValidate_AcceptsFullySupportedTarget()
    {
        PowerLimitTargetValidationResult result = PowerLimitTargetValidator.Validate(
            new PowerLimitTarget(12, 25, 45),
            new PowerLimitCapability(
                SupportsStapm: true,
                SupportsFast: true,
                SupportsSlow: true));

        Assert.True(result.IsValid);
        Assert.Null(result.Error);
    }
}
