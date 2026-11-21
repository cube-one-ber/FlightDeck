# Status

Goal: FlightDeck v1 — a Rust daemon/CLI, an Omarchy Quickshell bar widget, and a Qt 6 / Kirigami Mission Control app backed by the Next Spaceflight API (reverse engineered with REA).

Done
- Daemon/CLI (`daemon/`), Quickshell bar widget (`widget/`), Qt 6 / Kirigami Mission Control app (`app/`), Arch packaging & systemd user service (`pkgbuild/`, `bin/`), README with updated screenshot (`docs/screenshot.png`).
- Mission Control UI redesigned in Qt 6 + Kirigami following GNOME and Apple HIG (GNOME winning clashes) with Papirus symbolic icons (`SymbolicIconProvider`), full live Omarchy dark/light palette + Hyprland corner rounding (`Theme`), flat `HeaderBar` + centered view switcher + Primary Menu, boxed-list cards, interactive segmented campaign progress, condition-aware weather icons, two-zone launch countdown hero, boxed day groups, bottom floating toast overlay, and full-window modal keyboard shortcuts dialog.
- `bin/test`: 16 Rust tests and 9 Qt tests pass. Both release binaries build cleanly with zero QML warnings.
- Council reviews completed:
  - Architecture & Code (initial v1): Claude Opus 5.5 **9/10**, Gemini 4 Neon **8.5/10**.
  - Bar popup redesign: Claude Opus 5.5 **8/10**, GPT-6 Luna **9/10**.
  - Qt + Kirigami Mission Control UI redesign — Code & Architecture Council (R1–R5): Grok 4.7 **8.5 → 9.4/10 (Pass)** (stopped after R4 per user), GPT-6 Luna **8 → 9 → 9 → 9.7 → 9.8/10 (Pass)**, Gemini 4 Neon **7.5 → 8.5 → 9.5 → 9.6 → 9.9/10 (Pass)**.
  - Qt + Kirigami Mission Control UI redesign — Visual UI Council (Screenshots-Only, No Code, vs. Next Spaceflight, Flight Atlas, T-Minus, Space Launch Now, Supercluster, SpaceXNow; R1–R5): GPT-6 Luna **8.2 → 8.6 → 9.0 → 9.2 → 9.0/10** (plateaued at ~9.0–9.2 on live-data-only desktop scope vs. photo/map consumer apps), Gemini 4 Neon **8.4 → 9.4 → 9.8 → 9.5 → 9.6/10** (peak **9.8/10**; post-R5 light-theme cobalt checkmark contrast fix applied).

Next
- Installed and running on this machine (`flightdeck open` or launcher `Super + Space`). After widget changes: rebuild the package, reinstall, then `omarchy restart shell` (the bar does not watch plugin files).

Gotchas
- To preview the popup on the hidden monitor, stub `qs.Ui/PopupCard` with an inline Item: the real PopupWindow does not map without a bar, and `agent-gui run` does not pass env vars.
- `makepkg` needs `options=('!lto')`, or `ring` fails to link.
- The API encodes date precision in T-0 microseconds (`59` day/month, `70` quarter, `75` half, `80` year).
- `status_manager.id` stays `2` across flights, so overrides and milestone alerts are scoped by campaign title.
