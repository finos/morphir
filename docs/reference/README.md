---
sidebar_position: 5
sidebar_label: Reference
---

# Reference Documentation

Technical reference documentation for Morphir backends, APIs, and tools.

## 📋 Contents

### [Backends](backends/)

Platform-specific code generation backends:

#### Scala & Spark
- [Scala Backend](backends/scala-backend.md)
- [Scala API Usage](backends/scala-api-usage-docs.md)
- [Scala JSON Codecs Backend](backends/scala-json-codecs-backend.md)
- [Morphir Scala Code Generation](backends/morphir-scala-gen.md)
- [Spark Backend Design](backends/spark-backend-design.md)
- [Spark Backend API](backends/spark-backend-api-documentation.md)
- [Spark Backend Joins](backends/spark-backend-joins.md)
- [Spark Backend Optional Values](backends/spark-backend-optional-values.md)
- [Spark as Relational Backend](backends/spark-backend-as-a-special-case-of-a-relational-backend.md)
- [Spark Testing Framework](backends/spark-testing-framework.md)

#### Other Platforms
- [Relational Backend](backends/relational-backend.md)
- [TypeScript](backends/typescript.md)
- [TypeScript API](backends/morphir-typescript-api.md)
- [CADL/TypeSpec](backends/cadl-doc.md)
- [Spring Boot](backends/spring-boot-readme.md)

### [JSON Schema](json-schema/)

JSON Schema generation and configuration:

- [JSON Codecs Documentation](json-schema/json-codecs-doc.md)
- [Generating JSON Schema](json-schema/generating-json-schema.md)
- [JSON Schema Configuration](json-schema/json-schema-config.md)
- [JSON Schema Mappings](json-schema/json-schema-mappings.md)
- [JSON Schema Sample](json-schema/json-schema-sample.md)
- [JSON Schema Developers Guide](json-schema/json-schema-enabled%20developers%20guide.md)
- [Codec Documentation](json-schema/codec-docs.md)

### [CLI Reference](cli/)

Command-line interface documentation:

- [CLI Incremental Build](cli/morphir-cli-incremental-build-approach.md)
- [CLI Merging Documentation](cli/cli-cli2-merging-docs.md)

### Other Reference Materials

- [Testing Framework](testing-framework-readme.md)
- [Insight](insight-readme.md)
- [User Guide](user-guide-readme.md)
- [Versioning](versioning.md)
- [Error: Append Not Supported](error-append-not-supported.md)
- [Table Template](table-template.md)

## 🎯 How to Use This Section

This reference section is organized by technology and purpose:

- **Looking for a specific backend?** Check the [backends/](backends/) folder
- **Working with JSON?** See [json-schema/](json-schema/)
- **CLI questions?** Browse [cli/](cli/)

## 🔍 Quick Reference

### Common Tasks

- **Generate Scala code**: See [Scala Backend](backends/scala-backend.md)
- **Generate TypeScript**: See [TypeScript](backends/typescript.md)
- **Work with JSON Schema**: See [Generating JSON Schema](json-schema/generating-json-schema.md)
- **Understanding CLI**: See [CLI Reference](cli/)

### Backend Comparison

Different backends serve different purposes:

- **Scala/Spark**: For JVM-based execution and big data processing
- **TypeScript**: For web applications and Node.js
- **JSON Schema**: For API documentation and validation
- **Spring Boot**: For enterprise Java applications
- **Relational**: For database query generation

## 📚 Related Documentation

- Learn the concepts in [Core Concepts](../concepts/)
- See practical usage in [User Guides](../user-guides/)
- Contribute backend improvements via [Developer Guides](../developers/)

---

[← Back to Documentation Home](../README.md)
