# AMD Mobile Power

AMD Mobile Power is an open-source Windows utility for controlling and
monitoring power limits on supported AMD laptops, with a focus on
thin-and-light systems.

> Status: early development. The current repository is being migrated from a
> working single-machine prototype into a maintainable native application.

## Planned Features

- Native WinForms GUI with taskbar and notification-area integration.
- Privileged worker process isolated from the UI.
- AC and battery power presets.
- Real-time STAPM, Fast, Slow, temperature, and effective-limit telemetry.
- Automatic CPU family, SMU interface, and PM table detection.
- Read-back verification and firmware-limit diagnostics.
- Portable ZIP and installed release variants.
- Compatibility profiles and a documented hardware matrix.

## Safety

Changing firmware power limits can cause instability, overheating, battery
wear, data loss, or hardware damage. Use conservative values. This project is
not affiliated with AMD or laptop manufacturers.

Some platforms lock sustained limits in BIOS or the embedded controller. A
successful RyzenAdj call does not guarantee that the requested value survives
read-back.

## Development

See:

- `docs/DEV_STATUS.md` for the current state and next task.
- `docs/ROADMAP.md` for milestones.
- `docs/ARCHITECTURE.md` for component boundaries.
- `docs/IPC.md` for the GUI-to-worker protocol.
- `AGENTS.md` for maintenance rules.

## License

Original project code is licensed under the MIT License. Third-party components
retain their own licenses. See `THIRD_PARTY_NOTICES.md` once dependencies are
vendored.

