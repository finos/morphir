#!/usr/bin/env bun
// #MISE description="Run all type checking"
// #MISE alias="tc"
// #MISE depends=["wit:verify"]

// This task aggregates all type checking tasks.
// Currently runs: wit:verify
// Future: could add Go type checking, schema validation, etc.

console.log("All type checks passed!");
