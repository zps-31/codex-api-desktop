# Security

## Supported version

Security fixes are applied to the latest release, currently 2.14.x.

## Credential handling

- API keys are stored in macOS Keychain.
- The local proxy binds only to `127.0.0.1`.
- Remote API endpoints that use credentials must use HTTPS.
- Redirects may not forward credentials to a different origin.
- API keys are not exported to the launched Codex process environment.
- Profiles that do not require a key do not trigger Keychain value reads.

## Defensive limits

The proxy accepts only `POST /v1/responses` and applies limits to request bodies,
chunked encoding, response bodies, downstream queues, local session files, and
task bridge files. Custom authentication header names are validated and unsafe
hop-by-hop headers are rejected.

## Reporting

Open a private security advisory in the GitHub repository. Do not include real
API keys, session logs, account details, or provider credentials in an issue.

## Release verification

Release builds must pass strict Debug and Release compilation, the built-in
self-test on supported architecture slices, bundle validation, zip integrity,
and signature verification. `DISTRIBUTION=1` additionally requires Developer ID
signing, Hardened Runtime, timestamping, Apple notarization, stapling, and
Gatekeeper acceptance.

The locally generated test artifact is ad-hoc signed because this machine does
not currently contain a Developer ID certificate.
