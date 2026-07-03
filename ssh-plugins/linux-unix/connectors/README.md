# Linux/Unix SSH Connectors

Alternative SSH transport implementations for the Linux/Unix CPM plugin and PSM connector. Each sub-folder replaces the raw `#ssh#` directive in `Process.ini` with a specific SSH client library, giving finer control over authentication, ciphers, host-key validation, and error handling.

## Available Connectors

| Connector | Library | Use Case |
|-----------|---------|----------|
| [`plink/`](plink/) | PuTTY `plink.exe` | PSM session proxy; scripted CPM verify/change via batch or PowerShell |
| [`rebex/`](rebex/) | Rebex SSH (commercial .NET) | CPM External Plugin; keyboard-interactive auth; fine-grained cipher control |
| [`renci/`](renci/) | SSH.NET by Renci (open-source .NET) | CPM External Plugin; key-based auth; open-source alternative to Rebex |

## When to Choose Each

```
Need a PSM session window (interactive SSH)?
  └── plink/

Need CPM verify/change/reconcile with full .NET control?
  ├── Commercial support required?      → rebex/
  └── Open-source / no license cost?   → renci/
```

## Shared Prerequisites

- CyberArk PAM 12.0+ with CPM and/or PSM installed
- .NET Framework 4.7.2+ or .NET 6+ on the CPM/PSM Windows server (for Rebex / Renci connectors)
- `plink.exe` from [PuTTY](https://www.chiark.greenend.org.uk/~sgtatham/putty/) v0.78+ (for plink connector)
