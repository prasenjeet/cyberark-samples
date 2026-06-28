# Custom Application SSH CPM Plugin Template

A starting-point template for integrating any SSH-accessible application with CyberArk CPM. Copy this folder, rename it, and adapt the command sequences in `Process.ini` to match the target application's CLI prompts.

## When to Use This Template

Use this template when the target system:

- Is accessible via SSH but is not a standard OS or network device
- Presents a custom CLI or menu-driven interface over SSH
- Requires a specific sequence of commands to change a credential
- Cannot be managed by any of the pre-built plugins

Common examples:
- Database appliances with a management SSH shell
- Network-attached storage (NAS) management interfaces
- Industrial control system (ICS) management shells
- Mainframe SSH gateways
- Custom internal tooling with SSH access

## Files

| File | Purpose |
|------|---------|
| `Plugin.ini` | Plugin metadata — fill in `Name` with your app's name |
| `Process.ini` | **Primary customization file** — adapt commands and prompts |
| `scripts/detect_prompts.sh` | Helper script to capture CLI prompts during development |
| `scripts/test_session.sh` | Replay a recorded session to validate command sequences |

## Customization Checklist

1. **Rename the plugin folder** to match your application (e.g., `my-database-appliance`).
2. **Edit `Plugin.ini`** — update `Name` and adjust the `PasswordPolicy` to the application's requirements.
3. **Capture the CLI prompts** — run `scripts/detect_prompts.sh` against the target and note exact prompt strings.
4. **Edit `Process.ini`** — replace placeholder `ExpectedOutputN` values with the captured prompts.
5. **Test** — run `scripts/test_session.sh` to validate the full sequence before deploying to CPM.
6. **Deploy** — copy to the CPM plugins directory and import the platform.
