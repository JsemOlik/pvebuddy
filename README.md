
![Logo](https://github.com/JsemOlik/pvebuddy/blob/main/Assets/banner.png?raw=true)

# PVE Buddy

A clean, privacy‑respecting iOS app for monitoring and managing your Proxmox VE cluster. Built with SwiftUI, Charts, and async/await. No telemetry, no external services — your data stays on your phone.

## Highlights

- Dashboard
  - Live CPU, RAM, swap, I/O wait
  - Storage usage with totals and free space
  - Auto‑refresh + pull‑to‑refresh

- Virtual Machines
  - Cluster‑wide list (filter by node)
  - VM detail with live CPU/RAM and uptime
  - Quick actions: Start, Shutdown, Force Stop, Reboot
  - Hardware info grouped from config
  - Distro badges via tags

- Edit Resources
  - Change vCPU (cores, sockets), memory, optional balloon RAM
  - Live node capacity shown while editing (RAM and CPU wait)
  - Slider snaps to 0.5 GB up to 64 GB + free‑form entry

- Console (noVNC)
  - In‑app Web Console via browser ticket (PVEAuthCookie)
  - Web login stored locally (username/password/realm)

- Settings
  - Appearance (Light/Dark/System)
  - Server + API token
  - Web Console login
  - Local notifications (placeholders for future categories)

## Requirements

- iOS 17+
- Xcode 15+
- Proxmox VE reachable via internet
- Proxmox API Token (for REST API)
- Proxmox username/password/realm (for Web Console ticket)

## Quick Start

1. Open in Xcode or run on device/simulator.
2. Enter your server URL (e.g. https://pve.example.com:8006) and API token.
3. (Optional) Fill Settings → Web Console Login to enable noVNC.

## Auth Notes

- API: uses PVEAPIToken for Proxmox REST.
- Console: requires a browser session cookie (PVEAuthCookie) obtained from `/api2/json/access/ticket` using username/password/realm. API tokens don’t work for the Web UI.

## Security & Privacy

- Credentials stored locally via `@AppStorage` (UserDefaults).
- No third‑party analytics or outbound traffic besides your Proxmox server.
- For self‑signed certs, trust may be needed on device.

## Troubleshooting

- 401 in console: ensure Web Console Login is set, realm is correct (pam/pve), and URL/cert are valid.
- Resource changes not applying: some Proxmox changes (cores/memory) may require shutdown/reboot. Balloon RAM needs guest support.

## License

GNU GENERAL PUBLIC LICENSE — see COPYING.

## Credits

Made with ❤️ by Oliver Steiner (JsemOlik)
