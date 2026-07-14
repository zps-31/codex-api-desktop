# Changelog

## 2.14.5 - 2026-07-13

- Completed header-only HTTP requests without waiting for the client to close,
  so unsupported methods and paths fail immediately.
- Distinguished incomplete request frames from malformed ones, capped headers
  at 64 KiB, and rejected duplicate or conflicting body-framing headers.
- Added parser regressions for empty bodies, partial bodies, negative lengths,
  ambiguous framing, duplicate lengths, and overflowing chunks.
- Removed the final forced unwrap from latest-session file selection.

## 2.14.4 - 2026-07-13

- Removed the API desktop launch fallback to the official Codex application.
  API configuration and its private environment can now only be passed to the
  separately identified `Codex API Plus` runtime.
- Clarified missing and damaged API-runtime errors so a failed API launch
  cannot be mistaken for an official Codex issue.

## 2.14.3 - 2026-07-13

- Recovered Keychain access when the per-user default/search-list preference
  is missing by opening the real macOS account login Keychain explicitly.
- Kept Keychain lookup independent from API Codex `HOME` isolation and added
  legacy service-name fallback with lazy migration.
- Added a secret-free Keychain write/update/read/delete diagnostic for release
  checks.
- Replaced truncated-name process termination with full executable-path
  matching so local rebuilds cannot leave an older manager instance running.
- Reads a 256 KiB session tail first and expands only when necessary, reducing
  status-bar CPU and transient memory while retaining the 4 MiB fallback.

## 2.14.2 - 2026-07-13

- Migrated stale per-user workspace paths automatically while preserving
  unavailable external-volume paths.
- Hardened profile/config parsing, upstream URL construction, model catalog
  generation, session discovery, and bounded private log rotation.
- Reapplied private permissions to existing runtime directories and state files
  on every launch instead of relying on first-creation permissions.
- Skipped damaged or architecture-incompatible Codex applications so Intel and
  Apple Silicon Macs can fall back to a compatible official installation.

## 2.14.1 - 2026-07-13

- Fully isolated API Codex from the official ChatGPT account by assigning
  private `HOME`, Core Foundation home, XDG directories, `CODEX_HOME`, and
  Electron user data to every launched API desktop process.
- Removed inherited OpenAI/Codex credentials and endpoint overrides before
  launch, preventing API model choices from leaking into official Codex.
- Preserved portable fallback to the official Codex app while allowing both
  instances to run concurrently with independent configuration and state.

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
