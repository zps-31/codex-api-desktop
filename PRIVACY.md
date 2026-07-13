# Privacy

Effective date: 2026-07-12

Codex API Desktop Plus does not include advertising, analytics, or a developer-
operated telemetry service. Configuration and launch history remain on the Mac.

- API keys are stored in macOS Keychain.
- Profiles and preferences are stored under
  `~/Library/Application Support/Codex API Manager Plus/`.
- Model requests are sent to the API provider selected by the user.
- The bundled local route listens only on `127.0.0.1`.
- The separately launched Codex application may contact services required by
  Codex itself; those services have their own privacy terms.

The developer does not sell application data. Users can remove local data by
deleting the application support folder and related Keychain entries. Security
reports should use the repository's private security advisory feature.
