# Rebex SSH Connector

CPM External Plugin for Linux/Unix using the [Rebex SSH library](https://www.rebex.net/ssh/) (.NET). Provides full programmatic control over the SSH session: cipher negotiation, keyboard-interactive authentication, host-key fingerprint pinning, and detailed error categorisation.

## Why Rebex

- **Keyboard-interactive auth** — required by some AIX, HP-UX, and hardened SSHD configurations that disable password auth but allow `keyboard-interactive`
- **Host-key fingerprint pinning** — validate the server's fingerprint at connection time, not just at first-connect like `StrictHostKeyChecking`
- **Ed25519 / ECDSA key support** on .NET Framework 4.x (before Microsoft's SSH support was mature)
- **Commercial support and SLA** — important for regulated environments requiring vendor support

## Files

| File | Purpose |
|------|---------|
| `CPMRebex-Plugin.ps1` | CPM External Plugin — Verify, Change, Reconcile |
| `packages.config` | NuGet dependency declaration |
| `download-rebex.ps1` | One-time script to download Rebex assemblies from NuGet |

## Prerequisites

1. A valid [Rebex SSH](https://www.rebex.net/ssh/) license (trial available).
2. Download the NuGet package: run `download-rebex.ps1` on the CPM server.
3. .NET Framework 4.7.2+ on the CPM server (comes pre-installed on Server 2019/2022).

## Deployment

1. Run `download-rebex.ps1` to place `Rebex.Net.Ssh.dll` alongside the plugin:
   ```powershell
   .\download-rebex.ps1
   ```
2. Copy `CPMRebex-Plugin.ps1` and the Rebex DLLs to:
   ```
   C:\Program Files (x86)\CyberArk\Password Manager\Plugins\UnixSSH\
   ```
3. In `Process.ini`, set `ExternalPlugin=CPMRebex-Plugin.ps1`.

## Keyboard-Interactive Auth

Some Linux targets (and most AIX/HP-UX systems) use `keyboard-interactive` auth
where sshd sends one or more prompts (e.g., "Password:", "OTP:"). Rebex handles
this via the `KeyboardInteractiveAuthenticationRequest` event. The plugin
implements a default handler that responds with the password to any single-prompt
challenge; extend `Invoke-KIAuthHandler` for OTP or multi-factor challenges.
