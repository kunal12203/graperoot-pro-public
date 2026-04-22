# GrapeRoot Pro — Public Launcher Assets

This repo hosts the installer scripts and launcher binaries for GrapeRoot Pro.
The actual Pro engine (MCP server + graph builder) is in a separate **private** repo
and fetched only with a valid license.

Customers run:

```bash
# macOS / Linux
curl -fsSL https://graperoot.dev/pro/install.sh | bash -s -- GRP-XXXX-XXXX-XXXX

# Windows (PowerShell)
$env:GRAPEROOT_LICENSE_KEY = "GRP-XXXX-XXXX-XXXX"
irm https://graperoot.dev/pro/install.ps1 | iex
```

Buy a license: https://graperoot.dev/pro
Support: support@graperoot.dev
