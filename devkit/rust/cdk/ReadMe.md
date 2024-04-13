# Morphir CDK

**Morphir Code Model Development Kits** In the context of Morphir, CDKs are libraries which provide a programming language specific representation of the Morphir code model. This allows you to work with Morphir models in your favorite programming language.

## Supported Languages

| Language | Status |
|----------|--------|
| Scala | ![Static Badge](https://img.shields.io/badge/status-incubating-yellow)|
| Rust  | ![Static Badge](https://img.shields.io/badge/status-incubating-yellow)|

## What's In a CDK?

```mermaid
block-beta
columns 3
IR["Morphir IR"] MDM["Morphir Data Model"] MG["Morphir Graph"]
space space space
block:group1:3
    CDK["Morphir Code Model Development Kit (CDK)"]
end
IR --> CDK
MDM --> CDK
MG --> CDK
```
