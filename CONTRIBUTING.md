# Contributing

Thank you for your interest in contributing to the sLiq Protocol. This document provides guidelines for contributions.

## Development Setup

```bash
git clone https://github.com/earn-park/sliq-protocol.git
cd sliq-protocol
forge install
forge build
forge test
```

## Code Style

- Solidity 0.8.30+ with `via_ir` compilation
- Run `forge fmt` before submitting changes
- Follow existing NatSpec documentation patterns
- Use custom errors instead of `require()` strings
- Use `SafeERC20` for all token transfers

## Testing

All changes must include tests. Run the full suite before submitting:

```bash
forge test                     # all tests must pass
forge fmt --check              # formatting must be clean
```

### Test Organization

- `test/unit/` -- unit tests per contract
- `test/fuzz/` -- property-based fuzz tests
- `test/mocks/` -- mock contracts for external dependencies

## Pull Requests

1. Fork the repository and create a feature branch
2. Make your changes with tests
3. Run `forge build && forge test && forge fmt --check`
4. Submit a PR with a clear description of changes

## Security

If you discover a security vulnerability, please report it privately. See [SECURITY.md](./SECURITY.md) for details.

## License

By contributing, you agree that your contributions will be licensed under the project's [BUSL-1.1](./LICENSE) license.
