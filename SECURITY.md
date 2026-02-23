# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in the sLiq Protocol, please report it responsibly.

**Do NOT open a public GitHub issue for security vulnerabilities.**

Instead, please email: **security@earnpark.com**

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact assessment
- Suggested fix (if any)

## Response Timeline

- **Acknowledgment:** within 48 hours
- **Assessment:** within 1 week
- **Fix timeline:** depends on severity

## Scope

The following are in scope for security reports:

- Smart contracts in `src/`
- Deployment scripts in `script/`
- Configuration files that affect on-chain behavior

The following are out of scope:

- Third-party dependencies in `lib/` (report upstream)
- Documentation errors
- Gas optimizations

## Audit Status

| Date | Auditor | Scope | Status |
|------|---------|-------|--------|
| 2026-02-23 | Internal review | Full protocol | Completed |
| TBD | Third-party (planned) | Full protocol | Planned pre-mainnet |

## Known Limitations

See [`docs/SECURITY.md`](./docs/SECURITY.md) for detailed trust assumptions, known limitations, and invariants.

## Bug Bounty

A formal bug bounty program will be announced after the third-party audit is completed.
