# Changelog

## 2.14.0 - 2026-07-12

- Fixed local Ollama and LM Studio profiles being hidden or blocked when no API Key is needed.
- Replaced repeated Keychain value reads with lightweight existence checks.
- Fixed unsafe symbol-image assumptions and hardened response-size validation.
- Tightened billing-domain matching to exact domains and subdomains.
- Stopped stale task timers and local proxy instances during store teardown.
- Added universal Apple Silicon and Intel packaging, custom app icons, checksums,
  and a fail-closed Developer ID notarization workflow.

## 2.13.0 - 2026-07-12

- Added current-session, latest-request, and context-window usage metrics.
- Added profile copy and delete actions.
- Fixed localhost proxy interference and duplicate proxy instances.
- Fixed streaming response decoding when upstream compression is enabled.
- Added same-origin redirect enforcement and bounded network/file processing.
- Prevented API keys from entering the launched Codex process environment.

## 2.12.0 - 2026-07-12

- Added real-time session usage to the manager status bar.
- Improved upstream error details for failed Responses API requests.
