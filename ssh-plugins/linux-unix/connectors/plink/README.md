# Plink SSH Connector (PuTTY)

Uses `plink.exe` (PuTTY's command-line SSH client) as the transport for both
PSM session proxying and scripted CPM verify/change/reconcile operations on
Linux/Unix targets.

## Files

| File | Purpose |
|------|---------|
| `PSMPlink-Connection.xml` | PSM connection component — import via PVWA |
| `PSMPlink-UnixSSH.ps1` | PowerShell PSM connector wrapper (launched by PSM) |
| `CPMPlink-Plugin.ps1` | PowerShell CPM External Plugin using plink for all three operations |
| `plink-ssh.bat` | Lightweight batch launcher for simple password-based sessions |

## Why Plink

- Bundled in every Windows environment that already uses PuTTY
- Native `.ppk` private key support (no conversion needed from PuTTYgen)
- Keyboard-interactive auth support important for AIX/HP-UX targets
- PSM can embed a plink session directly in the HTML5 or thick-client gateway
- Mature, auditable open-source binary with a long track record in CyberArk deployments

## Prerequisites

1. Download `plink.exe` from https://www.chiark.greenend.org.uk/~sgtatham/putty/
2. Copy to: `C:\Program Files\PuTTY\plink.exe` (or update `$PlinkPath` in the scripts)
3. Register the host key for target hosts to avoid interactive host-key prompts:
   ```
   plink.exe -ssh user@target-host -pw <pass> -batch echo ok
   # Accept the host key when prompted the first time
   ```
   Or distribute the known_hosts via registry: `HKCU\Software\SimonTatham\PuTTY\SshHostKeys`

## Deployment

### PSM Connector
1. Import `PSMPlink-Connection.xml` in PVWA → Platform Management → Connection Components.
2. Copy `PSMPlink-UnixSSH.ps1` to `C:\Program Files (x86)\CyberArk\PSM\Components\`.
3. Associate the connection component with the `UnixSSH` platform.

### CPM Plugin
1. Copy `CPMPlink-Plugin.ps1` to `C:\Program Files (x86)\CyberArk\Password Manager\Plugins\UnixSSH\`.
2. Reference it in `Process.ini` via `ExternalPlugin=CPMPlink-Plugin.ps1`.

## Plink Key Auth

To use an SSH private key instead of a password, store the `.ppk` file path (or PEM
content) in the account's ExtraPass field and pass it to plink via `-i`:

```powershell
& $PlinkPath -ssh $Address -P $Port -l $Username -i $KeyFile -batch $Command
```

PuTTY's `puttygen.exe` can convert OpenSSH PEM keys to `.ppk` format:
```
puttygen.exe id_ed25519 -o id_ed25519.ppk
```
