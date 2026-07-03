# Renci SSH.NET Connector

CPM External Plugin for Linux/Unix using [SSH.NET](https://github.com/sshnet/SSH.NET) by Renci — the most widely adopted open-source SSH library for .NET. No license cost, actively maintained, and available on NuGet as `SSH.NET`.

## Why SSH.NET (Renci)

- **Free and open-source** (MIT license) — no commercial dependency
- **Strong key-based auth** — RSA, ECDSA, Ed25519, DSA with or without passphrase
- **Multiple reconcile keys** — load all keys into a `PrivateKeyConnectionInfo` and let SSH.NET try each
- **Large ecosystem** — extensive community examples for CyberArk CPM integration
- **PowerShell-native** — integrates cleanly with CPM's PowerShell External Plugin framework

## Files

| File | Purpose |
|------|---------|
| `CPMRenci-Plugin.ps1` | CPM External Plugin — Verify, Change, Reconcile with multi-key support |
| `packages.config` | NuGet dependency declaration |
| `download-sshnet.ps1` | One-time script to download SSH.NET assembly from NuGet |

## Prerequisites

1. Run `download-sshnet.ps1` on the CPM server to pull `Renci.SshNet.dll`.
2. .NET Framework 4.7.2+ on the CPM server.
3. No license required.

## Deployment

1. Download the assembly:
   ```powershell
   .\download-sshnet.ps1
   ```
2. Copy `CPMRenci-Plugin.ps1` and `Renci.SshNet.dll` to:
   ```
   C:\Program Files (x86)\CyberArk\Password Manager\Plugins\UnixSSH\
   ```
3. Set `ExternalPlugin=CPMRenci-Plugin.ps1` in `Process.ini`.

## Multiple Key Support

SSH.NET's `PrivateKeyConnectionInfo` accepts an array of `PrivateKeyFile` objects.
The plugin automatically loads all three reconcile keys (ExtraPass1–3) that are
configured as key-type accounts. SSH.NET offers each key to the server in turn
until one authenticates — no extra dispatcher logic needed.

```powershell
$keys = @(
    New-Object Renci.SshNet.PrivateKeyFile($keyFile1),
    New-Object Renci.SshNet.PrivateKeyFile($keyFile2),
    New-Object Renci.SshNet.PrivateKeyFile($keyFile3)
)
$connInfo = New-Object Renci.SshNet.PrivateKeyConnectionInfo($host, $port, $user, $keys)
```
