# Platform Profiles

Profiles describe conservative limits and capabilities for a CPU family or
specific laptop. They do not grant hardware support by themselves.

## Schema

Each profile is one JSON object:

```json
{
  "schemaVersion": 1,
  "id": "hawk-point-8845hs",
  "displayName": "Hawk Point 8845HS development profile",
  "cpuFamilyPatterns": ["ryzenadj:10"],
  "processorNamePatterns": ["*8845HS*"],
  "pmTablePatterns": ["4c0009"],
  "minimumWatts": 5,
  "maximumWatts": 60,
  "defaultWatts": 25,
  "supportsStapm": true,
  "supportsFast": true,
  "supportsSlow": true,
  "notes": []
}
```

Patterns support `*` and `?`. Empty pattern arrays match any value. More
specific profiles win based on processor, PM table, and CPU family pattern
counts.

`cpuFamilyPatterns` can match either the Windows CPUID identity (`25:117`) or
the family identifier returned by RyzenAdj (`ryzenadj:10`). The worker records
both when available. RyzenAdj-family matching is preferred for generation-wide
profiles because Windows does not consistently expose CPUID family/model.

Profiles are hints and safety bounds. The hardware adapter must still probe the
actual PM table and validate read-back.

## Family Profiles

The repository includes conservative family profiles for RyzenAdj families
that have no device-level validation in this project:

| Profile | RyzenAdj families |
|---|---|
| `ryzenadj-legacy` | Raven, Picasso, Dali, Van Gogh |
| `ryzenadj-renoir-cezanne` | Renoir, Cezanne, Lucienne |
| `ryzenadj-rembrandt-phoenix` | Rembrandt, Phoenix |
| `ryzenadj-mendocino` | Mendocino |
| `ryzenadj-dragon-fire` | Dragon Range, Fire Range |
| `ryzenadj-krackan-strix` | Krackan Point, Strix Point |
| `ryzenadj-strix-halo` | Strix Halo |

These profiles only constrain presets and target ranges. They do not prove
that a laptop supports writes, that its PM table is correct, or that firmware
will accept a requested value.

