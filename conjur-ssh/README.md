# Conjur SSH Certificate-Based Authentication

Demonstrates how to integrate CyberArk Conjur with OpenSSH to issue short-lived SSH certificates for users and workloads, eliminating long-lived SSH keys and static passwords.

## How It Works

```
  User / Workload
       │
       │  1. Authenticate to Conjur (LDAP, OIDC, IAM, etc.)
       ▼
  ┌──────────┐
  │  Conjur  │  2. Issues a short-lived SSH certificate
  │   CA     │     (signed by Conjur's SSH CA key)
  └────┬─────┘
       │  3. User presents certificate to target
       ▼
  Target SSH Server
  (trusts Conjur CA ─ no per-user authorized_keys needed)
```

## Benefits Over Traditional SSH

| Traditional SSH | Conjur SSH Certificates |
|-----------------|------------------------|
| Long-lived static keys | Certificates expire in minutes/hours |
| `authorized_keys` must be managed on every host | Hosts only need to trust the CA |
| Key sprawl — hard to audit who has access | Every cert issuance is logged in Conjur |
| Revoking access requires removing keys from all hosts | Simply stop issuing certificates |

## Files

| File | Purpose |
|------|---------|
| `policy/ssh-ca-policy.yml` | Conjur policy: CA key, roles, and permissions |
| `policy/workload-policy.yml` | Conjur policy: workload identity and certificate grants |
| `scripts/setup_ca.sh` | Initialize Conjur as an SSH CA |
| `scripts/issue_certificate.sh` | Request an SSH certificate from Conjur |
| `scripts/configure_sshd.sh` | Configure OpenSSH on target hosts to trust Conjur CA |

## Quick Start

```bash
# 1. Load policies into Conjur
conjur policy load -b root -f policy/ssh-ca-policy.yml
conjur policy load -b root -f policy/workload-policy.yml

# 2. Initialize the CA on the Conjur server
./scripts/setup_ca.sh

# 3. Configure each target SSH server
./scripts/configure_sshd.sh --host target-server.example.com

# 4. Issue a certificate for a user (run on the user's workstation)
./scripts/issue_certificate.sh --role users/alice --ttl 4h
# Outputs: ~/.ssh/id_ed25519-cert.pub (valid for 4 hours)

# 5. Connect using the certificate — no password, no static key
ssh -i ~/.ssh/id_ed25519 alice@target-server.example.com
```

## Certificate TTL Recommendations

| Use Case | Recommended TTL |
|----------|----------------|
| Developer interactive session | 8 hours |
| CI/CD pipeline job | 30 minutes |
| Emergency break-glass | 1 hour (with dual approval) |
| Service-to-service (automated) | 5 minutes (auto-renewed) |
