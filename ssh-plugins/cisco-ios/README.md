# Cisco IOS SSH CPM Plugin

Manages local user account passwords and the Enable Secret on Cisco IOS and IOS-XE network devices via SSH. Supports password rotation for both the local user database and the privileged exec (enable) password.

## Supported Platforms

- Cisco IOS 12.4+
- Cisco IOS-XE 3.x+
- Cisco IOS-XR (basic support)
- Cisco Catalyst (IOS-based)
- Cisco ASR, ISR router families

## Files

| File | Purpose |
|------|---------|
| `Plugin.ini` | Plugin metadata and password policy |
| `Process.ini` | IOS CLI command sequences for all three CPM operations |

## Account Types

This plugin handles two distinct account types — configure the `AccountType` property accordingly:

| `AccountType` | Manages |
|---------------|---------|
| `LocalUser` | `username <user> secret <password>` entries |
| `EnableSecret` | `enable secret` privileged exec password |

## Account Properties

| Property | Description | Example |
|----------|-------------|---------|
| `Address` | Router/switch IP or hostname | `10.1.1.1` |
| `UserName` | IOS local username | `netadmin` |
| `Port` | SSH port | `22` |
| `AccountType` | `LocalUser` or `EnableSecret` | `LocalUser` |
| `EnablePassword` | Current enable password (for verification) | *(from Vault)* |

## Prerequisites on the Cisco Device

```
! Enable SSH version 2
ip ssh version 2
ip ssh time-out 60
ip ssh authentication-retries 3

! Ensure local auth is enabled
aaa authentication login default local
aaa authorization exec default local

! Verify a local user exists for CPM to manage
username netadmin privilege 15 secret <initial-password>
```

## Troubleshooting

- **Error: % Login invalid** — The stored password does not match the IOS local user account.
- **Error: % Access denied** — The user does not have privilege level 15 or exec authorization is misconfigured.
- **Timeout at enable prompt** — Set `EnablePassword` on the account and verify `aaa authorization exec default local` is configured.
