# Linux/Unix SSH CPM Plugin

Manages local user account passwords on Linux and Unix systems via SSH. Supports password change, verification, and reconciliation using the standard `passwd` utility.

## Supported Platforms

- RHEL / CentOS / Fedora
- Ubuntu / Debian
- SUSE Linux Enterprise
- Oracle Linux
- AIX (with `/usr/bin/passwd`)
- HP-UX

## Files

| File | Purpose |
|------|---------|
| `Plugin.ini` | Plugin metadata, allowed safes, and password policy |
| `Process.ini` | SSH session commands for all three CPM operations |
| `scripts/ChangePass.sh` | Called by CPM to execute the password change |
| `scripts/VerifyPass.sh` | Called by CPM to verify the current credential |
| `scripts/ReconcilePass.sh` | Called by CPM to reconcile using a privileged account |

## Account Properties

| Property | Description | Example |
|----------|-------------|---------|
| `Address` | Hostname or IP of the target server | `192.168.1.100` |
| `UserName` | Local account to manage | `appuser` |
| `Port` | SSH port (default 22) | `22` |
| `ReconcileAccount` | Privileged account used for reconcile | `root` |

## Deployment

1. Copy this folder to the CPM server:
   ```
   C:\Program Files (x86)\CyberArk\Password Manager\Plugins\UnixSSH\
   ```

2. Import `UnixSSH-Platform.xml` into the Vault.

3. Create accounts in the Vault with Platform = `UnixSSH`.

## Troubleshooting

- **Error: Permission denied** — Verify the reconcile account has `sudo` rights or is root.
- **Error: passwd: Authentication token manipulation error** — Check PAM configuration on the target host.
- **Timeout during logon** — Verify the SSH port is reachable from the CPM server and `StrictHostKeyChecking` is configured correctly.
