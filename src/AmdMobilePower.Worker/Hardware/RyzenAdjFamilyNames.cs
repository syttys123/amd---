namespace AmdMobilePower.Worker.Hardware;

public static class RyzenAdjFamilyNames
{
    public static string GetName(int family)
    {
        return family switch
        {
            -2 => "Waiting for load",
            -1 => "Unknown",
            0 => "Raven",
            1 => "Picasso",
            2 => "Renoir",
            3 => "Cezanne",
            4 => "Dali",
            5 => "Lucienne",
            6 => "Van Gogh",
            7 => "Rembrandt",
            8 => "Mendocino",
            9 => "Phoenix",
            10 => "Hawk Point",
            11 => "Dragon Range",
            12 => "Krackan Point",
            13 => "Strix Point",
            14 => "Strix Halo",
            15 => "Fire Range",
            _ => $"Family {family}"
        };
    }
}
