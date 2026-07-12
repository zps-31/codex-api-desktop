# Security

## Credential handling

- API keys are stored in macOS Keychain.
- The local proxy binds only to `127.0.0.1`.
- Remote API endpoints that use credentials must use HTTPS.
- Redirects may not forward credentials to a different origin.
- API keys are not exported to the launched Codex process environment.

## Defensive limits

The proxy accepts only `POST /v1/responses` and applies limits to request bodies,
chunked encoding, response bodies, downstream queues, local session files, and
task bridge files. Custom authentication header names are validated and unsafe
hop-by-hop headers are rejected.

## Reporting

Please open a private security advisory in this repository. Do not include real
API keys, session logs, or provider credentials in an issue.

## Verification

The 2.13.0 release passed:

- `swift build`
- `swift run CodexAPIManagerPlus --self-test`
- Ad-hoc signature verification with `codesign --verify --deep --strict`
- A real streaming Responses API request through `127.0.0.1:62139`

The app is ad-hoc signed and is not Apple-notarized.
