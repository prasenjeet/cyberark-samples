# PSM SSH Connection Component

Configuration for the CyberArk Privileged Session Manager (PSM) to proxy and record SSH sessions to target systems. The PSM acts as a transparent SSH gateway — users connect to the PSM which in turn connects to the target using credentials retrieved from the Vault.

## Architecture

```
User (SSH Client)
      │
      │  ssh user@psm-host -p 22
      ▼
┌─────────────────┐
│   PSM Server    │  ← Retrieves credential from Vault
│  (SSH Gateway)  │  ← Records the full session
└────────┬────────┘
         │  ssh <target_user>@<target_host>
         ▼
   Target System
   (Linux, Network
    Device, etc.)
```

## Files

| File | Purpose |
|------|---------|
| `connection-component.xml` | PSM connection component definition (import via PVWA) |
| `psm-ssh-sshd_config.snippet` | Relevant `sshd_config` settings for the PSM SSH service |

## How It Works

1. The user runs: `ssh <vault-username>@<psm-address>` with optional `-p <port>`.
2. PSM authenticates the user against the Vault or LDAP/RADIUS.
3. PSM fetches the target account credentials from the Vault.
4. PSM opens an SSH connection to the target system.
5. All keystrokes and output are recorded as a session audit in the Vault.
6. The session is visible and playable in PVWA → Session Management.

## Deployment

1. Log in to PVWA as an administrator.
2. Navigate to **Administration → Platform Management → Connection Components**.
3. Click **Import Connection Component** and upload `connection-component.xml`.
4. Associate the connection component with one or more Platforms.
5. Users can then click **Connect** on any account that uses that Platform.

## Session Recording

Sessions are stored as `.avi` recordings in the Vault's `PSMRecordings` safe by default. Live monitoring is available under **PVWA → Active Sessions**.
