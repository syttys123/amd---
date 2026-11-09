# Architecture Decisions

## ADR-001: Native GUI Instead of PowerShell

Status: accepted

PowerShell-hosted WinForms windows inherit the PowerShell taskbar identity.
Replacing the GUI shell with a native executable gives stable taskbar, icon,
tray, and single-instance behavior.

## ADR-002: Separate Privileged Worker

Status: accepted

The GUI must not own RyzenAdj handles or run with unnecessary privileges.
Hardware access belongs in one worker process with a narrow IPC contract.

## ADR-003: Read-Back Is Mandatory

Status: accepted

The 8845HS prototype demonstrated that RyzenAdj can report a successful STAPM
write while the firmware reads back a lower limit. All writes require read-back
verification and an effective-limit status.

## ADR-004: No Bilibili Login Automation

Status: accepted

Release media may be prepared automatically. Account login and final upload
must use an already authenticated session and must not automate credential or
security prompts.

