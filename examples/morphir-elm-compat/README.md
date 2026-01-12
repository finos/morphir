# Morphir-Elm Compatibility Example

This example project demonstrates a complete morphir-elm compatible project structure
that can be used for integration testing the Go toolchain's morphir-elm integration.

## Project Structure

```
morphir-elm-compat/
├── elm.json              # Elm package configuration
├── morphir.json          # Morphir project configuration
├── src/
│   └── ElmCompat/
│       ├── Main.elm      # Core types and business logic
│       └── Api.elm       # API request/response types
├── test.yaml             # Integration test expectations
└── .gitignore            # Excludes generated files
```

## Building

To compile the Elm code to Morphir IR:

```bash
npx morphir-elm make
```

This produces `morphir-ir.json` containing the compiled intermediate representation.

## Module Overview

### ElmCompat.Main

Core business domain types:
- `Product`, `ProductId`, `Quantity` - Product-related types
- `CustomerOrder`, `OrderStatus` - Order management types
- `calculateTotal`, `applyDiscount`, `isValidOrder` - Business logic functions

### ElmCompat.Api

API layer types:
- `Request`, `Response` - API message types
- `ApiError` - Error handling type
- `createOrder`, `getOrderStatus`, `processRequest` - API operations

## Integration Testing

This project is used to verify the Go toolchain's morphir-elm integration:

1. The toolchain invokes `npx morphir-elm make` via the NPX backend
2. The resulting `morphir-ir.json` is validated for correct structure
3. The IR can be used as input for code generation tests

See `test.yaml` for the expected IR structure and test assertions.
