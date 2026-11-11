# Compatibility Report Template

Submit public reports through the repository issue form. Remove account names,
personal paths, serial numbers, and unrelated desktop content before attaching
diagnostics.

Generate the read-only report from the extracted portable package:

```powershell
powershell -ExecutionPolicy Bypass `
  -File .\collect-native-diagnostics.ps1 `
  -OutputPath .\compatibility.json `
  -MarkdownPath .\compatibility.md
```

The collector does not enable power-limit writes, does not upload data, and
uses a field whitelist plus path sanitization. Review the JSON before attaching
it publicly. The optional Markdown file is an issue-ready summary; review it
before attaching it to a public issue.

Maintainers import a reviewed report into the repository index with:

```powershell
.\native\import-compatibility-report.ps1 `
  -ReportPath .\compatibility.json
```

The importer rejects reports that do not declare all privacy flags false,
reports from a write-enabled worker, local drive paths, user-profile paths, and
named-pipe names. Current reports must also carry a valid `profileCatalog`
where every RyzenAdj family `0-15` maps to exactly one fallback and exactly one
device profile is marked verified. The importer deduplicates by SHA256,
archives the sanitized JSON under `docs/evidence/compatibility`, updates
`docs/evidence/compatibility/index.json`, and regenerates
`docs/COMPATIBILITY_REPORTS.md`. It does not upload anything.

The report already carries a `host` block with manufacturer, model, BIOS
version, Windows edition/version/build, and a `privacy` block that states no
paths, process IDs, account names, serial numbers, logs, or upload were
included. Copy those values into the Device section below instead of retyping
them from system settings; only add what the collector cannot know, such as the
active laptop performance or quiet mode.

## Device

- Vendor and model:
- CPU name:
- BIOS version:
- Windows edition and build:
- Laptop performance/quiet mode:

## Runtime Evidence

- App version or source commit:
- Read-only snapshot works: yes / no
- Power line during test: AC / battery
- RyzenAdj family number and name:
- SMU BIOS interface:
- PM table:
- Matched profile:
- Available profile IDs:
- Hardware adapter configured: yes / no
- Worker write controls enabled: yes / no
- STAPM actual/limit:
- PPT Fast actual/limit:
- PPT Slow actual/limit:
- Temperature:

## Conflicts

- Running `RyzenPower`, `ryzenadj`, or AMD Ryzen Master: yes / no
- Legacy `\AMD\RyzenAdj*` task state:
- `Local\RyzenAdjPowerWorker` present:
- `Local\AmdMobilePower.HardwareOwner.v1` present:

## Diagnostics

- Diagnostics schema version:
- Worker/protocol version:
- Worker executable SHA256:
- Packaged read-only diagnostic export attached: yes / no
- Diagnostics JSON attached: yes / no
- `collectionStatus` is `PASS`: yes / no
- Worker write controls were disabled: yes / no
- Graceful worker shutdown reported: yes / no
- Runtime-file hashes included: yes / no
- GUI/worker log excerpts included: no for standard GUI/collector exports;
  explain any manually added excerpts
- Log directory:
- Sensitive information reviewed and removed: yes / no

## Stability

- Firmware clamp observed:
- Worker timeout or native crash observed:
- Reboot required after driver fault: yes / no
- Additional notes:
