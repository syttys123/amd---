# Platform Profiles

Profiles describe conservative limits and capabilities for a CPU family or
specific laptop. They do not grant hardware support by themselves. The native
worker compiles the catalog from `native/cpp-worker/src/profile_catalog.cpp`
and exposes the complete catalog read-only through the `getProfiles` IPC
command.

## Selection

The worker first checks the device-specific match:

```text
RyzenAdj family 10 + processor name contains 8845HS + PM table 4c0009
  -> hawk-point-8845hs
```

Otherwise every family from `0` through `15` maps to exactly one conservative
family fallback. Family mapping is preferred for generation-wide profiles
because Windows does not consistently expose CPUID family/model, while
RyzenAdj returns a stable family identifier.

Profiles are safety bounds, not proof of write support. The hardware adapter
must still probe the actual PM table, validate capabilities, and read back
every write.

## Family Profiles

The repository includes conservative family profiles for RyzenAdj families
that have no device-level validation in this project:

| Profile | RyzenAdj families |
|---|---|
| `ryzenadj-legacy` | `0` Raven, `1` Picasso, `4` Dali, `6` Van Gogh |
| `ryzenadj-renoir-cezanne` | `2` Renoir, `3` Cezanne, `5` Lucienne |
| `ryzenadj-rembrandt` | `7` Rembrandt |
| `ryzenadj-phoenix` | `9` Phoenix |
| `ryzenadj-mendocino` | `8` Mendocino |
| `ryzenadj-dragon-fire` | `11` Dragon Range, `15` Fire Range |
| `ryzenadj-krackan-strix` | `12` Krackan Point, `13` Strix Point |
| `ryzenadj-strix-halo` | `14` Strix Halo |
| `ryzenadj-hawk-point` | `10` Hawk Point, excluding the verified 8845HS/4c0009 match |

These profiles only constrain presets and target ranges. They do not prove
that a laptop supports writes, that its PM table is correct, or that firmware
will accept a requested value.

The test suite requires every RyzenAdj family identifier from `0` through `15`
to appear exactly once across the shipped family-fallback set. It also requires
exactly one verified device profile. Adding support for a new family therefore
requires an explicit catalog and test update rather than silently falling into
an unrelated generation.

