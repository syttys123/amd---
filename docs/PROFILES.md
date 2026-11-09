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
  "cpuFamilyPatterns": ["*"],
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

Profiles are hints and safety bounds. The hardware adapter must still probe the
actual PM table and validate read-back.

