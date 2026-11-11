# Headless Compatibility Diagnostics

`amd-mobile-power-probe.exe` is the dependency-free diagnostic entry point that
ships next to the GUI and worker in every native package. It answers a single
question: *does AMD Mobile Power understand this laptop?* It answers without
the GUI, without PowerShell, and without ever enabling hardware writes.

This exists because the first useful step on an unknown AMD machine is a report
that can be reviewed and imported, not a write to the SMU.

## Quick start

From an extracted package:

```powershell
.\amd-mobile-power-probe.exe --diagnose
```

The JSON report is written to standard output. To keep both a machine-readable
report and a human summary:

```powershell
.\amd-mobile-power-probe.exe --diagnose `
  --out .\compatibility.json `
  --markdown .\compatibility.md
```

For a quick check that the binary itself is intact (no hardware access, safe in
CI and on a fresh machine):

```powershell
.\amd-mobile-power-probe.exe --self-test
```

## What a diagnosis does

1. Starts a private copy of `amdmobilepower_native_worker.exe` with a unique
   pipe name derived from the probe process id and a timestamp.
2. Checks `Local\AmdMobilePower.HardwareOwner.v1` first: if the installed GUI
   already owns hardware access, the probe reports that explicitly instead of
   failing inside the driver.
3. Passes `--enable-hardware` but never `--enable-write-controls`, so the
   worker can read SMU telemetry and rejects every write command.
4. Collects `getHealth`, `getCapabilities`, `getSnapshot`, `getProfiles`, and
   `getPowerPolicy`.
5. Reads SMBIOS and Windows version strings from the registry.
6. Sends `shutdown`, waits for the worker to exit, and kills it if it does not.
7. Emits one JSON document and, optionally, a Markdown summary.

Hardware access is exclusive: the worker takes
`Local\AmdMobilePower.HardwareOwner.v1` and a second owner is rejected. If the
GUI is already running, or the driver cannot be opened, the probe keeps the run
useful: it restarts the worker without `--enable-hardware`, still records host
information, worker health, and the profile catalog, and reports
`collectionStatus: "FAILED"` with a clear reason instead of crashing. Exit the
app from the tray and rerun for live limits.

## Report shape

The document uses the same schema as `collect-native-diagnostics.ps1`, so
`native/import-compatibility-report.ps1` accepts either source:

```json
{
  "schemaVersion": 1,
  "reportType": "amd-mobile-power-native-compatibility",
  "collectionStatus": "PASS",
  "collectedAt": "2026-11-12T05:10:00Z",
  "collector": {
    "name": "amd-mobile-power-probe",
    "version": "0.1.0",
    "mode": "headless-diagnose",
    "requiresPowerShell": false,
    "requiresGui": false
  },
  "privacy": {
    "localPathsIncluded": false,
    "pipeNameIncluded": false,
    "processIdIncluded": false,
    "accountNamesIncluded": false,
    "serialNumbersIncluded": false,
    "recentLogsIncluded": false,
    "networkUploadPerformed": false
  },
  "host": { "manufacturer": "...", "model": "...", "biosVersion": "..." },
  "package": { "name": "...", "version": "...", "sourceCommit": "..." },
  "worker": { "status": "ok", "hardwareInitialized": true, "writeControlsEnabled": false },
  "platform": { "processorName": "...", "isSupported": true, "profile": { } },
  "profileCatalog": { "schemaVersion": 1, "profiles": [ ] },
  "telemetry": { "powerLine": "ac", "stapmLimitWatts": 10.0 },
  "powerPolicy": { },
  "powerPolicyNote": "state of the private diagnostic worker, not the installed app's saved policy",
  "checks": [ { "id": "worker.health", "status": "PASS", "detail": "..." } ],
  "error": null
}
```

`checks` is a flat list of `id` / `status` (`PASS`, `WARN`, `FAIL`) / `detail`
entries so a reviewer can see *why* a run failed without reading the whole
document.

## Exit codes

| Code | Meaning |
|---|---|
| `0` | `collectionStatus` is `PASS` |
| `2` | Collection failed; the report still explains why |

## Privacy

- No local paths, pipe names, process ids, account names, serial numbers, or
  recent logs are included.
- Nothing is uploaded; the probe has no network code.
- The report is written only where the caller points `--out` and `--markdown`.

## Importing a report

```powershell
pwsh -File .\native\import-compatibility-report.ps1 `
  -ReportPath .\compatibility.json
```

The importer re-validates the schema, privacy flags, profile catalog coverage,
and path redaction before indexing the report under
`docs/evidence/compatibility/`.

## Verified run

`docs/evidence/diagnostics/headless-probe-8845hs-live-2026-11-12.json` records a
full `PASS` from the expanded `1.0.11-native` ZIP with the tray app closed:
`hardwareInitialized=true`, `writeControlsEnabled=false`, matched
`hawk-point-8845hs`, and live AC `10/10/10 W`. The following run against the
installed GUI shows the `worker.exclusive` warning instead.

## Release gate

`native/build.ps1` builds the probe and runs its unit tests. Packaging then:

- requires `amd-mobile-power-probe.exe` in the staged package;
- runs `--self-test` from the staged tree;
- runs `--diagnose` from the *expanded ZIP* during runtime verification and
  asserts `collectionStatus=PASS`, hardware initialized, write controls
  disabled, no privacy flag set, and no local path or pipe name in the output.

The diagnose step needs the same elevated context as the existing hardware
collector; the self-test runs everywhere.

## Raw single-request mode

The verifier scripts still drive a worker that was started elsewhere:

```powershell
.\amd-mobile-power-probe.exe --pipe-name "\\.\pipe\AmdMobilePower.Worker.v1" --command getSnapshot
```

That mode is unchanged and writes nothing.
