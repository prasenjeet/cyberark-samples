# Windows OpenSSH CPM Plugin

Manages local Windows user account passwords on servers running the built-in OpenSSH server (`OpenSSH-Server` Windows Feature). Uses PowerShell commands executed over the SSH session to rotate credentials.

## Supported Platforms

- Windows Server 2019, 2022
- Windows 10 / 11 (with OpenSSH Server enabled)
- Windows Server 2016 (with OpenSSH installed via GitHub release)

## Files

| File | Purpose |
|------|---------|
| `Plugin.ini` | Plugin metadata and password policy |
| `Process.ini` | SSH + PowerShell command sequences |
| `scripts/ChangePass.ps1` | PowerShell script for password rotation |

## Account Properties

| Property | Description | Example |
|----------|-------------|---------|
| `Address` | Windows server IP or FQDN | `winserver01.corp.local` |
| `UserName` | Local Windows account | `LocalAdmin` |
| `Port` | OpenSSH port (default 22) | `22` |
| `Domain` | Leave empty for local accounts | *(empty)* |

## Prerequisites on the Windows Server

```powershell
# Install OpenSSH Server
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0

# Start and enable the service
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic

# Configure PowerShell as the default shell for SSH sessions
New-ItemProperty -Path "HKLM:\SOFTWARE\OpenSSH" `
    -Name DefaultShell `
    -Value "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -PropertyType String -Force

# Allow SSH through Windows Firewall (usually done automatically)
Get-NetFirewallRule -Name *ssh*
```

## Troubleshooting

- **Error: Permission denied (publickey)** — Ensure password authentication is enabled: `PasswordAuthentication yes` in `C:\ProgramData\ssh\sshd_config`.
- **Error: Set-LocalUser not recognized** — PowerShell remoting shell is not the default shell; check `DefaultShell` registry key.
- **Password complexity failure** — Windows enforces its own password complexity policy; ensure CyberArk's policy meets or exceeds it.
