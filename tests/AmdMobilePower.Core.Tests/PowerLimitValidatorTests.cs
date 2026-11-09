using AmdMobilePower.Core.Validation;

namespace AmdMobilePower.Core.Tests;

public sealed class PowerLimitValidatorTests
{
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
}
