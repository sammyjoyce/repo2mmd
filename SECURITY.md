# Security Policy

## Supported Versions

repo2mmd is pre-release software. Security fixes land on `main` and in the
latest tagged release.

| Version | Supported |
| ------- | --------- |
| main    | ✅ |
| latest 0.x release | ✅ |
| older releases | ❌ |

## Reporting a Vulnerability

We take the security of repo2mmd seriously. Please avoid filing vulnerabilities
through public GitHub issues or pull requests.

### How to report
Use the **Report a vulnerability** button under the repository's
[Security tab](https://github.com/sammyjoyce/repo2mmd/security/advisories/new).
This opens a private advisory that only the maintainers can see.

When reporting, please include:
- A concise description of the issue and potential impact
- Minimal reproduction steps or proof-of-concept
- Affected commit hash or release tag
- Any configuration details required to reproduce the problem

### Response expectations
- **Acknowledgement** within 2 business days
- **Initial assessment** within 7 days
- **Status updates** at least weekly until resolution
- **Credit** in the advisory unless you prefer anonymity

We appreciate coordinated disclosure and will publish advisories once a fix is
available or a reasonable remediation window has elapsed.

## Best Practices for Users
- Run repo2mmd binaries from trusted sources only (official releases or your
  own builds).
- Verify downloaded archives against the release's `SHA256SUMS`.
- Review plugin code before loading third-party `.so`/`.dylib` artefacts.
- Configure CI secrets carefully; repo2mmd performs no outbound network
  requests but plugins may read repository contents.

