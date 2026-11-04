# Security policy

## Report a vulnerability privately

Use [GitHub's private vulnerability reporting form](https://github.com/Vantiger-Construction/neura_os/security/advisories/new)
to report suspected security or privacy vulnerabilities in Neura Companion OS.
Avoid public issues and pull requests for undisclosed vulnerabilities.

Include the affected commit or release, operating system, expected behavior,
observed impact, and a minimal reproduction using synthetic data. Relevant
boundaries include consent, memory access, deletion, encryption, microphone
lifecycle, offline adapters, and build or update integrity.

Do not include real journals, recordings, conversations, personal documents,
credentials, or access tokens. Redact sensitive values from logs and screenshots.
If a credential has been exposed, revoke or rotate it with its provider; deleting
a repository file does not revoke a credential or remove it from Git history.

Maintainers can discuss reproduction, impact, remediation, and disclosure through
the private report. Do not publish exploit details or affected user data while
coordination is in progress. No fixed response or remediation deadline is promised.

## Supported source

The active development branch is `Neura`. Include the exact source revision or
official release identifier so maintainers can determine whether the issue still
affects current code. Historical branches, PR artifacts, and development packages
do not imply a separately maintained security-support line.

For ordinary bugs without a security or privacy impact, use the
[issue tracker](https://github.com/Vantiger-Construction/neura_os/issues).
See [security validation](docs/SECURITY_VALIDATION.md) for scanner coverage,
evidence requirements, and limitations. Passing scans do not establish that a
build is vulnerability-free or ready for physical-device use.
