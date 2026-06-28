# CyberArk SSH Plugin Samples

A collection of sample CyberArk SSH-based plugins for the Central Policy Manager (CPM), Privileged Session Manager (PSM), and Conjur secret management. These samples demonstrate how to build, configure, and deploy SSH plugins for common target systems.

## Contents

| Directory | Description |
|-----------|-------------|
| [`ssh-plugins/linux-unix/`](ssh-plugins/linux-unix/) | CPM plugin for Linux/Unix accounts via SSH |
| [`ssh-plugins/cisco-ios/`](ssh-plugins/cisco-ios/) | CPM plugin for Cisco IOS network devices |
| [`ssh-plugins/juniper-junos/`](ssh-plugins/juniper-junos/) | CPM plugin for Juniper JunOS devices |
| [`ssh-plugins/windows-openssh/`](ssh-plugins/windows-openssh/) | CPM plugin for Windows OpenSSH server accounts |
| [`ssh-plugins/custom-app/`](ssh-plugins/custom-app/) | Template CPM plugin for custom SSH-accessible applications |
| [`psm-ssh-connector/`](psm-ssh-connector/) | PSM SSH connection component configuration |
| [`conjur-ssh/`](conjur-ssh/) | Conjur SSH certificate-based authentication integration |

## Prerequisites

- CyberArk Privileged Access Manager (PAM) 12.0+
- Central Policy Manager (CPM) with SSH capability
- Privileged Session Manager (PSM) for session recording (optional)
- CyberArk Conjur 1.9+ for certificate-based SSH (optional)

## How CyberArk SSH Plugins Work

```
┌─────────────┐       SSH       ┌───────────────┐
│     CPM     │ ──────────────► │ Target System │
│  (Password  │ ◄────────────── │ (Linux/Cisco/ │
│  Rotation)  │   Response      │  Juniper...)  │
└─────────────┘                 └───────────────┘
       │
       │  Stores new
       │  credential
       ▼
┌─────────────┐
│   Vault     │
│ (Password   │
│  Store)     │
└─────────────┘
```

### CPM Plugin Lifecycle

Each CPM SSH plugin must implement three operations:

1. **Verify** — Connect via SSH and confirm the stored credential is valid.
2. **Change** — Connect via SSH and change the account password to a newly generated value.
3. **Reconcile** — Connect using a privileged reconcile account and reset the target account password.

### Plugin File Structure

```
PluginName/
├── Plugin.ini      # Plugin metadata and password policy settings
├── Process.ini     # SSH commands for Verify/Change/Reconcile
└── scripts/        # Optional helper scripts called by Process.ini
```

## Quick Start

1. Copy the desired plugin folder to the CPM server at:
   `C:\Program Files (x86)\CyberArk\Password Manager\Plugins\<PluginName>\`

2. Import the matching Platform definition into the Vault via:
   `PrivateArk Client → Tools → Import Platform`

3. Associate accounts in the Vault with the imported Platform.

4. Trigger a CPM verify/change operation and review the `pm.log` for results.

## Security Notes

- All SSH connections use `StrictHostKeyChecking` configured per environment requirements.
- No credentials are ever hard-coded — all secrets are fetched from the Vault at runtime using CPM parameter substitution (`%Parameter%`).
- Reconcile accounts should be stored in a dedicated, tightly controlled Safe.

## License

These samples are provided for educational purposes under the [MIT License](LICENSE).
