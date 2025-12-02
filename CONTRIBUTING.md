# Contributing to PVE Buddy

Thanks for considering a contribution! This guide explains how to set up, code, and submit changes to PVE Buddy.

## Development Setup

1. Fork the repo
2. Clone your fork:
   ```bash
   git clone https://github.com/<your-username>/pvebuddy.git
   cd pvebuddy
   ```
3. Create a feature branch:
   ```bash
   git checkout -b feat/<short-feature-name>
   ```
4. Open the project in Xcode (15+) and select a simulator (iOS 17+).
5. Build and run.

## Project Structure (high level)

- `ProxmoxClient.swift` — all Proxmox REST calls (nodes, VMs, RRD, actions, config, web ticket)
- `DashboardView(.swift) + DashboardViewModel.swift`
- `VMsView(.swift) + VMsViewModel.swift`
- `VMDetailView(.swift) + VMDetailViewModel.swift`
- `WebConsoleView.swift` — in‑app noVNC via WKWebView + cookie injection
- `Settings/*` — appearance, notifications, server info, web login
- `Models` inline with client for simplicity

Please keep UI in SwiftUI and business logic in view models or client.

## Coding Guidelines

- Swift 5, SwiftUI, async/await
- MVVM: views = UI only, view models = state & orchestration, client = IO
- Prefer value types, immutability, and clear naming
- Use `@MainActor` for UI‑bound models
- Keep PRs focused and small

## Conventional Commits

Use Conventional Commits for PR titles and commit messages:
- `feat`: A new feature (triggers MINOR version bump)
- `fix`: A bug fix (triggers PATCH version bump)
- `docs`: Documentation only changes (no version bump)
- `style`: Changes that do not affect the meaning of the code (no version bump)
- `refactor`: A code change that neither fixes a bug nor adds a feature (no version bump)
- `perf`: A performance improvement (triggers PATCH version bump)
- `test`: Adding missing tests or correcting existing tests (no version bump)
- `chore`: Changes to the build process or auxiliary tools (no version bump)

Breaking changes: `feat!:` or include `BREAKING CHANGE:` in the body.

Examples:
```text
feat(vm): edit resources with live node capacity
fix(console): inject PVEAuthCookie before loading noVNC
docs(readme): add quick start
```

## UI/UX

- Keep controls native and accessible
- Prefer system colors/semantic styles
- Respect Light/Dark/System appearance
- Avoid adding external UI libs

## Tests

This app is UI-heavy; add unit tests where it makes sense (formatting, parsing, lightweight logic). Manual test plan for PRs:
- Connect to a Proxmox test node
- Verify dashboard loads, node filter works
- VM list and detail refresh correctly
- Power actions behave (use a test VM)
- Console opens after Web Console Login
- Edit resources updates and node stats refresh live
- Sliders snap to 0.5 GB, respect bounds, and accept typed values

## Submitting a PR

1. Rebase on latest `main`
2. Ensure build succeeds (simulator iOS 17+)
3. Make sure you did not include secrets in code or screenshots
4. Open a PR with:
   - Clear title (Conventional Commit)
   - What/why/verification steps
   - Screenshots or short clips if UI is affected

## Security

Do not submit real tokens, passwords, or server URLs. If you spot a security issue, open an issue with minimal details and we’ll follow up.

## License

By contributing, you agree your contributions are MIT licensed as part of this repo.
