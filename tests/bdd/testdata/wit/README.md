# WIT Test Fixtures

This directory contains WIT (WebAssembly Interface Types) test fixtures used for BDD testing of the WIT bindings adapter.

## Structure

- `wasi/` - Simplified WASI (WebAssembly System Interface) packages for testing
  - `clocks.wit` - WASI clocks interface (simplified from wasi:clocks@0.2.0)

## Purpose

These fixtures are used to test:

1. **WIT Package Parsing** - Verify the bytecodealliance/wit decoder works correctly
2. **Adapter Integration** - Test conversion from wit.Resolve to Morphir domain model
3. **BDD Scenarios** - Provide realistic test data for Gherkin feature files

## Fixture Guidelines

- Keep fixtures **minimal but realistic**
- Based on **real WASI specifications** but simplified for testing
- **Document** any deviations from the official specs
- Use **semantic versioning** in package declarations

## References

- [Component Model WIT Spec](https://component-model.bytecodealliance.org/design/wit.html)
- [WASI Specifications](https://github.com/WebAssembly/WASI)
- [bytecodealliance/wit](https://pkg.go.dev/go.bytecodealliance.org/wit)
