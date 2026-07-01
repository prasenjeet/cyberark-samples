# Linux/Unix SSH CPM Plugin

Manages local user account passwords on Linux and Unix systems via SSH. Supports password change, verification, and reconciliation using the standard `passwd` / `chpasswd` utilities. Reconciliation supports up to **three reconcile accounts**, each independently configured as either **SSH key** or **password** authentication.

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
| `Process.ini` | SSH session commands for all CPM operations |
| `scripts/ChangePass.sh` | Executes the password change on the target host |
| `scripts/VerifyPass.sh` | Verifies the current credential on the target host |
| `scripts/ReconcilePass.sh` | Force-resets the password (called remotely over SSH) |
| `scripts/reconcile_dispatcher.sh` | Multi-account dispatcher for `RECONCILESSH_MULTIKEY` |
| `scripts/validate_recon_keys.sh` | Pre-deployment validation for SSH key reconcile accounts |

## Account Properties

| Property | Required | Description | Example |
|----------|----------|-------------|---------|
| `Address` | Yes | Hostname or IP of the target server | `192.168.1.100` |
| `UserName` | Yes | Local account to manage | `appuser` |
| `Port` | No (def: 22) | SSH port | `22` |
| `ExtraPass1Name` | No | Username of reconcile account 1 | `root` |
| `ExtraPass1AuthMethod` | No (def: `Password`) | `Password` or `Key` | `Key` |
| `ExtraPass2Name` | No | Username of reconcile account 2 | `deploy-admin` |
| `ExtraPass2AuthMethod` | No (def: `Password`) | `Password` or `Key` | `Key` |
| `ExtraPass3Name` | No | Username of reconcile account 3 (break-glass) | `breakglass` |
| `ExtraPass3AuthMethod` | No (def: `Password`) | `Password` or `Key` | `Key` |
| `ReconAccountCount` | No (def: `1`) | How many recon accounts are configured | `3` |

## Reconcile Sections

Choose the reconcile process in the Platform editor (PVWA → Platform Management → Platform → UI & Workflows → Reconcile):

| Section Name | When to Use |
|---|---|
| `RECONCILESSH` | Single reconcile account, password auth (backward-compatible default) |
| `RECONCILESSH_KEY1` | Single reconcile account, SSH key auth |
| `RECONCILESSH_KEY2` | Direct use of ExtraPass2 with SSH key |
| `RECONCILESSH_KEY3` | Direct use of ExtraPass3 with SSH key (break-glass) |
| `RECONCILESSH_PASS2` | Direct use of ExtraPass2 with password |
| `RECONCILESSH_PASS3` | Direct use of ExtraPass3 with password (break-glass) |
| `RECONCILESSH_MULTIKEY` | **Recommended** — automatically tries all configured accounts in order |

## Multi-Account Reconcile (RECONCILESSH_MULTIKEY)

When you select `RECONCILESSH_MULTIKEY`, the CPM invokes `reconcile_dispatcher.sh` which:

1. Reads `ExtraPass1` → `ExtraPass3` from the Vault account object
2. For each account (in priority order 1 → 2 → 3):
   - If `ExtraPassNAuthMethod=Key`: writes the PEM key to a secure temp file, connects via `ssh -i <tempfile>`, wipes the temp file on exit
   - If `ExtraPassNAuthMethod=Password`: connects via `sshpass`
3. On each successful connection, calls `ReconcilePass.sh` on the target to reset the password
4. Returns `RECON_SUCCESS:<index>:<username>` to CPM on first success
5. Returns `RECON_FAILURE:...` only if all configured accounts are exhausted

```
CPM (RECONCILESSH_MULTIKEY)
  └─► reconcile_dispatcher.sh
        ├─► ExtraPass1 (Key)   → ssh -i key1  → ReconcilePass.sh ✓ → RECON_SUCCESS:1:root
        │   (if fails ↓)
        ├─► ExtraPass2 (Key)   → ssh -i key2  → ReconcilePass.sh ✓
        │   (if fails ↓)
        └─► ExtraPass3 (Pass)  → sshpass ssh  → ReconcilePass.sh ✓
```

## SSH Key Storage in the Vault

Store SSH private key content (PEM format) directly in the **Password** field of the reconcile account object in the Vault:

```
Safe:    ReconAccounts
Folder:  Root
Account: root-ssh-key-prod-servers
  Address:  (leave blank or set to a pattern)
  UserName: root
  Password: -----BEGIN OPENSSH PRIVATE KEY-----
            b3BlbnNzaC1rZXktdjEAAAAABG5vbmU...
            -----END OPENSSH PRIVATE KEY-----
```

Then link it to the managed account via `ExtraPass1Safe`, `ExtraPass1Folder`, `ExtraPass1Name`.

## Deployment

1. Copy this folder to the CPM server:
   ```
   C:\Program Files (x86)\CyberArk\Password Manager\Plugins\UnixSSH\
   ```

2. Validate your SSH keys before deploying:
   ```bash
   ./scripts/validate_recon_keys.sh \
       --host 10.0.1.50 --port 22 \
       --target-user appuser \
       --recon1-user root         --recon1-key /path/to/root_key \
       --recon2-user deploy-admin --recon2-key /path/to/deploy_key \
       --recon3-user breakglass   --recon3-key /path/to/bg_key
   ```

3. Import `UnixSSH-Platform.xml` into the Vault.

4. Create accounts with Platform = `UnixSSH` and set the `ExtraPass` account links.

5. Set the reconcile process to `RECONCILESSH_MULTIKEY` in the Platform editor.

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `RECON_FAILURE: account 1 Key auth failed` | Key not in `authorized_keys` on target | Add reconcile account's public key to `~root/.ssh/authorized_keys` |
| `RECON_FAILURE: sshpass not found` | `sshpass` missing on CPM server | Install: `yum install sshpass` / `apt install sshpass` |
| `ERROR: must run as root or with passwordless sudo` | Reconcile user lacks privileges | Add `NOPASSWD: /usr/sbin/chpasswd, /usr/sbin/usermod` to sudoers |
| `Password does not look like PEM` | Vault account stores wrong value | Paste raw PEM (including `-----BEGIN ... KEY-----` headers) into Password field |
| `passwd: Authentication token manipulation error` | PAM configuration issue on target | Check `/etc/pam.d/passwd` and ensure no conflicting rules |
