# Juniper JunOS SSH CPM Plugin

Manages local user account passwords on Juniper Networks devices running JunOS via SSH. Supports password rotation, verification, and reconciliation using the JunOS CLI `set system login user` configuration hierarchy.

## Supported Platforms

- Juniper SRX (firewall)
- Juniper MX, EX, QFX (routers/switches)
- Juniper vSRX, vMX (virtual)
- JunOS 12.1+

## Files

| File | Purpose |
|------|---------|
| `Plugin.ini` | Plugin metadata and password policy |
| `Process.ini` | JunOS CLI command sequences for all three CPM operations |

## Account Properties

| Property | Description | Example |
|----------|-------------|---------|
| `Address` | Device IP or FQDN | `10.0.0.1` |
| `UserName` | JunOS local username | `netops` |
| `Port` | SSH port | `22` |

## Prerequisites on the Juniper Device

```
# Configure SSH and local authentication
set system services ssh protocol-version v2
set system authentication-order password

# Create the managed user account
set system login user netops class super-user
set system login user netops authentication plain-text-password
# <enter initial password at prompt>

# Commit the configuration
commit
```

## Troubleshooting

- **Error: ssh_exchange_identification** — Verify `set system services ssh` is configured.
- **Error: commit failed** — Check that the reconcile account has `super-user` class.
- **Password not taking effect** — JunOS requires a `commit` after every configuration change; verify the `commit and-quit` step succeeded.
