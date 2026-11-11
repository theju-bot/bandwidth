# Bandwidth Monitor for Omarchy

Daily internet bandwidth monitor plugin for Omarchy / Quickshell. Shows live daily bandwidth consumption in the status bar and provides a detailed breakdown popup by application and 30-day historical usage.

![Bandwidth Monitor Preview](assets/preview.png)

## Features

- **Status Bar Widget**: Shows live daily internet usage (`󰖟 2.6 GB`) directly in the top bar.
- **Minimal, Clean Popup Panel**:
  - Live summary with upload on the left, then download, then total (`↑ 798 MB · ↓ 5.5 GB · Total: 6.3 GB`).
  - **Usage Tab**: Overview with side-by-side Upload and Download metric cards, traffic proportion bar, and top processes.
  - **Current Tab**: Live per-process data usage breakdown for all active applications.
  - **History Tab**: Daily data consumption archive for the past 14 days.
  - **VPN & Proxy Support**: Inspects raw socket packets directly, allowing accurate process-level traffic tracking even when routing through VPNs or proxies (v2ray, WireGuard, OpenVPN, Tailscale, etc.).
- **Efficient & Lightweight**: Minimalist design with zero unnecessary emoji bloat. Background accumulator daemon communicates with `bandwhich` via JSON streaming without high CPU overhead.

---

## Dependencies

This plugin requires **`python3`** and **`bandwhich`**.

### 1. Install `bandwhich`

On Arch Linux / Omarchy:
```bash
sudo pacman -S bandwhich
```
*(or via cargo: `cargo install bandwhich`)*

### 2. Grant Network Capture Capabilities

`bandwhich` needs permission to monitor raw network traffic and inspect process sockets without running as full root. Set the required Linux capabilities:

```bash
sudo setcap 'cap_sys_ptrace,cap_dac_read_search,cap_net_raw,cap_net_admin+ep' $(which bandwhich)
```

---

## Installation

Install using the Omarchy plugin CLI:

```bash
omarchy plugin install https://github.com/theju-bot/bandwidth.git
```

Once installed, add `theju-bot.bandwidth` to your bar configuration in `~/.config/omarchy/bar.json` (or via Omarchy Bar Settings):

```json
{
  "right": [
    "theju-bot.bandwidth",
    ...
  ]
}
```

Reload Quickshell / Omarchy to start the widget.

---

## Data & Storage

Usage statistics and settings are kept in the standard user state directory:
- `~/.local/state/omarchy/theju-bot.bandwidth/stats.json`: Daily and per-app byte counters.
- `~/.local/state/omarchy/theju-bot.bandwidth/history.json`: Historical daily usage archives.
- `~/.local/state/omarchy/theju-bot.bandwidth/config.json`: User interface preferences (e.g. Minimal mode).

---

## Uninstallation

To remove the plugin:

```bash
omarchy plugin remove theju-bot.bandwidth
```

Optionally remove state and history data:

```bash
rm -rf ~/.local/state/omarchy/theju-bot.bandwidth
```

---

## License

[MIT](LICENSE) © 2026 Thesigan Yogarasa
