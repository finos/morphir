---
title: "Document Tree File Formats"
description: "Complete specification for VFS document tree file formats in Morphir IR V4"
---

# Document Tree File Formats

This document provides complete specifications for all file formats used in VFS (Virtual File System) mode, where Morphir IR distributions are stored as a directory tree with individual files for each definition.

## Overview

In VFS mode, a Morphir IR distribution is organized as:

```
.morphir-dist/
├── manifest.json                  # Distribution metadata
└── pkg/
    └── package-name/
        └── module-path/
            ├── module.json        # Module manifest
            ├── type-name.type.json    # Type definitions
            └── value-name.value.json  # Value definitions
```

## File Types

### 1. Distribution Manifest (`manifest.json`)

**Location**: `.morphir-dist/manifest.json`  
**Purpose**: Distribution-level metadata and configuration

**Required Fields**:
- `formatVersion`: IR format version (`"4.0.0"` or `4`)
- `distribution`: Distribution type (`"Library"`, `"Specs"`, or `"Application"`)
- `package`: Package name (canonical path format, e.g., `"my-org/my-project"`)

**Optional Fields**:
- `version`: Package version (semantic version string)
- `created`: Creation timestamp (ISO 8601 format)
- `layout`: Distribution layout (`"VfsMode"` or `"Classic"`, defaults to `"VfsMode"`)
- `entryPoints`: Entry points map (required for Application distributions)

**Schema**: See [morphir-ir-v4-document-tree-files.yaml](/schemas/morphir-ir-v4-document-tree-files.yaml) → `DistributionManifestFile`

**Example (Library)**:
```json
{
  "formatVersion": "4.0.0",
  "distribution": "Library",
  "package": "my-org/my-project",
  "version": "1.2.0",
  "created": "2026-01-15T12:00:00Z",
  "layout": "VfsMode"
}
```

**Example (Specs)**:
```json
{
  "formatVersion": "4.0.0",
  "distribution": "Specs",
  "package": "morphir/sdk",
  "version": "3.0.0",
  "created": "2026-01-15T12:00:00Z",
  "layout": "VfsMode"
}
```

**Example (Application)**:
```json
{
  "formatVersion": "4.0.0",
  "distribution": "Application",
  "package": "my-org/my-cli",
  "version": "2.0.0",
  "created": "2026-01-15T12:00:00Z",
  "layout": "VfsMode",
  "entryPoints": {
    "startup": {
      "target": "my-org/my-cli:main#run",
      "kind": "main",
      "doc": "Primary application entry point"
    },
    "build": {
      "target": "my-org/my-cli:commands#build",
      "kind": "command",
      "doc": "Build the project"
    }
  }
}
```

### 2. Module Manifest (`module.json`)

**Location**: `.morphir-dist/pkg/package-name/module-path/module.json`  
**Purpose**: Module metadata and optional inline definitions

**Required Fields**:
- `formatVersion`: IR format version (`"4.0.0"` or `4`)
- `path` or `module`: Module path (canonical format, e.g., `"my-org/domain"`)

> **Note on `path` vs `module` fields:**
>
> Both `path` and `module` fields are equivalent and accepted for backwards compatibility. The `path` field is preferred for new files. When reading `module.json` files, tools should accept either field name.

**Optional Fields**:
- `doc`: Module-level documentation (string or array of strings)
- `types`: Either array of type names (manifest style) or object with inline definitions (inline style)
- `values`: Either array of value names (manifest style) or object with inline definitions (inline style)

**Encoding Styles**:

#### Manifest Style (Granular)
Lists type/value names; definitions in separate files:

```json
{
  "formatVersion": "4.0.0",
  "path": "my-org/domain",
  "doc": "Domain model for main application",
  "types": ["user", "user-(id)", "order"],
  "values": ["get-user-by-email", "create-order", "validate-user"]
}
```

**Example with legacy `module` field** (equivalent to `path`):
```json
{
  "formatVersion": "4.0.0",
  "module": "my-org/domain",
  "doc": "Domain model for main application",
  "types": ["user", "order"],
  "values": ["create-order"]
}
```

#### Inline Style (Hybrid)
Contains definitions directly:

```json
{
  "formatVersion": "4.0.0",
  "path": "my-org/domain",
  "doc": "Domain model for main application",
  "types": {
    "user": {
      "access": "Public",
      "doc": "Represents a user",
      "TypeAliasDefinition": {
        "typeParams": [],
        "typeExp": {
          "Record": {
            "fields": {
              "email": "morphir/sdk:string#string"
            }
          }
        }
      }
    }
  },
  "values": {
    "create-user": {
      "access": "Public",
      "ExpressionBody": {
        "inputTypes": {},
        "outputType": "my-org/domain:types#user",
        "body": { "Literal": { "attributes": {}, "literal": { "StringLiteral": "..." } } }
      }
    }
  }
}
```

**Schema**: See [morphir-ir-v4-document-tree-files.yaml](/schemas/morphir-ir-v4-document-tree-files.yaml) → `ModuleManifestFile`

### 3. Type Definition File (`*.type.json`)

**Location**: `.morphir-dist/pkg/package-name/module-path/type-name.type.json`  
**Purpose**: Individual type definition or specification

**Required Fields**:
- `formatVersion`: IR format version (`"4.0.0"` or `4`)
- `name`: Type name (canonical format, must match filename without `.type.json` suffix)
- Exactly one of:
  - `def`: Type definition (implementation) - contains `TypeAliasDefinition`, `CustomTypeDefinition`, or `IncompleteTypeDefinition`
  - `spec`: Type specification (interface) - contains `TypeAliasSpecification`, `OpaqueTypeSpecification`, `CustomTypeSpecification`, or `DerivedTypeSpecification`

**Optional Fields**:
- `doc`: Documentation (string or array of strings) - can be at top level or nested in `def`/`spec`

**File Naming**:
- Use canonical name format (kebab-case)
- Suffix: `.type.json`
- Example: `user.type.json`, `user-(id).type.json`, `order-line-item.type.json`

**Schema**: See [morphir-ir-v4-document-tree-files.yaml](/schemas/morphir-ir-v4-document-tree-files.yaml) → `TypeDefinitionFile`

**Example (Definition)**:
```json
{
  "formatVersion": "4.0.0",
  "name": "user",
  "doc": "Represents a user in the system",
  "def": {
    "access": "Public",
    "TypeAliasDefinition": {
      "typeParams": [],
      "typeExp": {
        "Record": {
          "fields": {
            "user-id": "my-org/domain:types#user-(id)",
            "email": "morphir/sdk:string#string",
            "created-at": "my-org/sdk:local-date-time#local-date-time"
          }
        }
      }
    }
  }
}
```

> **Note on Design Document Examples:**
>
> Some examples in the design documents (`docs/design/draft/ir/distributions.md`) may be simplified and omit the `access` field for brevity. In actual VFS files that are part of a PackageDefinition, the `access` field is **required** in `def` objects. The examples in this specification document show the complete, valid format.

**Example (Specification)**:
```json
{
  "formatVersion": "4.0.0",
  "name": "int",
  "spec": {
    "doc": "Arbitrary precision integer",
    "OpaqueTypeSpecification": {}
  }
}
```

**Example (Custom Type Definition)**:
```json
{
  "formatVersion": "4.0.0",
  "name": "order-status",
  "def": {
    "access": "Public",
    "CustomTypeDefinition": {
      "typeParams": [],
      "access": "Public",
      "value": {
        "constructors": {
          "pending": [],
          "processing": [],
          "shipped": [],
          "delivered": [],
          "cancelled": []
        }
      }
    }
  }
}
```

### 4. Value Definition File (`*.value.json`)

**Location**: `.morphir-dist/pkg/package-name/module-path/value-name.value.json`  
**Purpose**: Individual value definition or specification

**Required Fields**:
- `formatVersion`: IR format version (`"4.0.0"` or `4`)
- `name`: Value name (canonical format, must match filename without `.value.json` suffix)
- Exactly one of:
  - `def`: Value definition (implementation) - contains wrapper object with `ExpressionBody`, `NativeBody`, `ExternalBody`, or `IncompleteBody`
  - `spec`: Value specification (interface) - contains `inputs` (object) and `output` (type)

**Optional Fields**:
- `doc`: Documentation (string or array of strings) - can be at top level or nested in `def`/`spec`

**File Naming**:
- Use canonical name format (kebab-case)
- Suffix: `.value.json`
- Example: `get-user-by-email.value.json`, `create-order.value.json`, `validate-email.value.json`

**Schema**: See [morphir-ir-v4-document-tree-files.yaml](/schemas/morphir-ir-v4-document-tree-files.yaml) → `ValueDefinitionFile`

**Example (Definition with ExpressionBody)**:
```json
{
  "formatVersion": "4.0.0",
  "name": "get-user-by-email",
  "doc": "Retrieve a user by email address",
  "def": {
    "access": "Public",
    "ExpressionBody": {
      "inputTypes": {
        "email": "morphir/sdk:string#string",
        "users": ["morphir/sdk:list#list", "my-org/domain:types#user"]
      },
      "outputType": ["morphir/sdk:maybe#maybe", "my-org/domain:types#user"],
      "body": {
        "Apply": {
          "attributes": {},
          "function": {
            "Reference": {
              "attributes": {},
              "fqname": "morphir/sdk:list#find",
              "args": []
            }
          },
          "argument": {
            "Variable": {
              "attributes": {},
              "name": "email"
            }
          }
        }
      }
    }
  }
}
```

> **Note on Type Reference Formats:**
>
> Type references in `inputTypes`, `outputType`, and `typeExp` fields can use either:
> - **Canonical string format**: `"morphir/sdk:string#string"` (preferred, more compact)
> - **Array format**: `["morphir/sdk:list#list", "my-org/domain:types#user"]` (for parameterized types)
>
> Both formats are valid. The canonical string format is preferred for simple types, while array format is used for parameterized types where the first element is the type constructor and subsequent elements are type arguments.

**Example (Definition with NativeBody)**:
```json
{
  "formatVersion": "4.0.0",
  "name": "add",
  "def": {
    "access": "Public",
    "NativeBody": {
      "inputTypes": {
        "a": "morphir/sdk:basics#int",
        "b": "morphir/sdk:basics#int"
      },
      "outputType": "morphir/sdk:basics#int",
      "nativeInfo": {
        "hint": { "Arithmetic": {} }
      }
    }
  }
}
```

**Example (Specification)**:
```json
{
  "formatVersion": "4.0.0",
  "name": "validate-email",
  "spec": {
    "doc": [
      "Validate an email address format.",
      "Returns true if the email is valid, false otherwise."
    ],
    "inputs": {
      "email": "morphir/sdk:string#string"
    },
    "output": "morphir/sdk:basics#bool"
  }
}
```

## Directory Structure

### Standard Layout

```
.morphir-dist/
├── manifest.json                         # Distribution metadata
└── pkg/
    └── my-org/
        └── my-project/                   # Package directory
            ├── domain/                   # Module directory
            │   ├── module.json          # Module manifest
            │   ├── user.type.json       # Type definition
            │   ├── user-(id).type.json  # Type definition
            │   ├── order.type.json      # Type definition
            │   ├── get-user.value.json  # Value definition
            │   └── create-order.value.json
            └── api/                     # Another module
                ├── module.json
                ├── request.type.json
                └── handle-request.value.json
```

### Nested Modules

Modules can be nested by creating subdirectories:

```
.morphir-dist/
└── pkg/
    └── my-org/
        └── my-project/
            └── domain/
                ├── module.json          # domain module
                ├── user.type.json
                └── orders/              # domain/orders submodule
                    ├── module.json      # domain/orders module
                    ├── order.type.json
                    └── shipping/        # domain/orders/shipping submodule
                        ├── module.json  # domain/orders/shipping module
                        └── address.type.json
```

## Field Details

### formatVersion

**Type**: String (semver) or Integer  
**Required**: Yes  
**Description**: IR format version

**Formats**:
- Semantic version: `"4.0.0"`, `"4.0.0-alpha.1"`, `"4.0.0+20240123"`
- Legacy integer: `4`

**Examples**:
```json
"formatVersion": "4.0.0"
"formatVersion": 4
```

### name

**Type**: Name (canonical string format)  
**Required**: Yes (in `*.type.json` and `*.value.json` files)  
**Description**: The canonical name of the type or value

**Format**: Kebab-case with optional parenthesized abbreviations
- `"user"`
- `"get-user-by-email"`
- `"value-in-(usd)"`
- `"user-(id)"`

**Constraint**: Must match the filename (without suffix)

### path / module

**Type**: ModuleName (canonical path format)  
**Required**: Yes (in `module.json`, either field)  
**Description**: Module path

**Format**: Forward-slash separated segments
- `"domain"`
- `"my-org/domain"`
- `"domain/orders/shipping"`

**Note**: `path` and `module` are equivalent; `path` is preferred for new files, while `module` is accepted for backwards compatibility with legacy files.

### doc

**Type**: String or Array of Strings  
**Required**: No  
**Description**: Documentation

**Formats**:
- Single-line: `"doc": "Brief description"`
- Multi-line: `"doc": ["Line 1", "Line 2", "Line 3"]`

**Location**: Can appear at:
- Top level of file
- Nested in `def` or `spec` object
- Both (top-level takes precedence for display)

### def

**Type**: Object  
**Required**: Yes (if this is a definition file)  
**Description**: Type or value definition (implementation)

**For Type Definitions**:
- Must contain exactly one of: `TypeAliasDefinition`, `CustomTypeDefinition`, `IncompleteTypeDefinition`
- Must include `access` field (`"Public"` or `"Private"`) when part of PackageDefinition
- May include `doc` field

**For Value Definitions**:
- Must contain wrapper object with exactly one of: `ExpressionBody`, `NativeBody`, `ExternalBody`, `IncompleteBody`
- Must include `access` field (`"Public"` or `"Private"`) when part of PackageDefinition
- May include `doc` field

**Example (Type)**:
```json
{
  "def": {
    "access": "Public",
    "doc": "User type",
    "TypeAliasDefinition": {
      "typeParams": [],
      "typeExp": "morphir/sdk:string#string"
    }
  }
}
```

**Example (Value)**:
```json
{
  "def": {
    "access": "Public",
    "doc": "Create a user",
    "ExpressionBody": {
      "inputTypes": {},
      "outputType": "my-org/domain:types#user",
      "body": { "Literal": { "attributes": {}, "literal": { "StringLiteral": "..." } } }
    }
  }
}
```

### spec

**Type**: Object  
**Required**: Yes (if this is a specification file)  
**Description**: Type or value specification (interface)

**For Type Specifications**:
- Must contain exactly one of: `TypeAliasSpecification`, `OpaqueTypeSpecification`, `CustomTypeSpecification`, `DerivedTypeSpecification`
- May include `doc` field

**For Value Specifications**:
- Must contain:
  - `inputs`: Object mapping parameter names to types
  - `output`: Type
- May include `doc` field

**Example (Type)**:
```json
{
  "spec": {
    "doc": "Integer type",
    "OpaqueTypeSpecification": {}
  }
}
```

**Example (Value)**:
```json
{
  "spec": {
    "doc": "Add two integers",
    "inputs": {
      "a": "morphir/sdk:basics#int",
      "b": "morphir/sdk:basics#int"
    },
    "output": "morphir/sdk:basics#int"
  }
}
```

## Access Control

### In PackageDefinition Context

When type/value files are part of a PackageDefinition:
- `def` objects **must** include `access` field
- Values: `"Public"` or `"Private"`
- Determines visibility within the package

### In PackageSpecification Context

When type/value files are part of a PackageSpecification:
- Only public items are included
- `spec` objects do **not** include `access` field (specs are always public)

## Advanced Examples

### Incomplete Type Definition

**user.type.json** (with incomplete definition):
```json
{
  "formatVersion": "4.0.0",
  "name": "user",
  "def": {
    "access": "Public",
    "IncompleteTypeDefinition": {
      "typeParams": [],
      "reason": {
        "UnresolvedReference": {
          "target": "my-org/domain:types#missing-type"
        }
      }
    }
  }
}
```

### External Value Definition

**external-api.value.json**:
```json
{
  "formatVersion": "4.0.0",
  "name": "call-external-api",
  "def": {
    "access": "Public",
    "ExternalBody": {
      "inputTypes": {
        "url": "morphir/sdk:string#string",
        "payload": "morphir/sdk:json#json"
      },
      "outputType": ["morphir/sdk:result#result", "morphir/sdk:json#json", "morphir/sdk:string#string"],
      "externalInfo": {
        "provider": "http",
        "endpoint": "/api/v1/data",
        "method": "POST"
      }
    }
  }
}
```

### Value with Complex Expression Body

**calculate-total.value.json**:
```json
{
  "formatVersion": "4.0.0",
  "name": "calculate-total",
  "doc": [
    "Calculate the total price of an order including tax.",
    "Applies discounts and regional tax rates."
  ],
  "def": {
    "access": "Public",
    "ExpressionBody": {
      "inputTypes": {
        "order": "my-org/domain:orders#order",
        "tax-rate": "morphir/sdk:basics#float"
      },
      "outputType": "morphir/sdk:basics#float",
      "body": {
        "LetDefinition": {
          "attributes": {},
          "valueName": "subtotal",
          "valueDefinition": {
            "ExpressionBody": {
              "inputTypes": {},
              "outputType": "morphir/sdk:basics#float",
              "body": {
                "Apply": {
                  "attributes": {},
                  "function": {
                    "Reference": {
                      "attributes": {},
                      "fqname": "morphir/sdk:list#sum",
                      "args": []
                    }
                  },
                  "argument": {
                    "Field": {
                      "attributes": {},
                      "subject": {
                        "Variable": {
                          "attributes": {},
                          "name": "order"
                        }
                      },
                      "fieldName": "line-items"
                    }
                  }
                }
              }
            }
          },
          "inValue": {
            "Apply": {
              "attributes": {},
              "function": {
                "Reference": {
                  "attributes": {},
                  "fqname": "morphir/sdk:basics#multiply",
                  "args": []
                }
              },
              "argument": {
                "Tuple": {
                  "attributes": {},
                  "elements": [
                    {
                      "Variable": {
                        "attributes": {},
                        "name": "subtotal"
                      }
                    },
                    {
                      "Apply": {
                        "attributes": {},
                        "function": {
                          "Reference": {
                            "attributes": {},
                            "fqname": "morphir/sdk:basics#add",
                            "args": []
                          }
                        },
                        "argument": {
                          "Tuple": {
                            "attributes": {},
                            "elements": [
                              {
                                "Literal": {
                                  "attributes": {},
                                  "literal": { "FloatLiteral": 1.0 }
                                }
                              },
                              {
                                "Variable": {
                                  "attributes": {},
                                  "name": "tax-rate"
                                }
                              }
                            ]
                          }
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
      }
    }
  }
}
```

### Type with Type Parameters

**result.type.json**:
```json
{
  "formatVersion": "4.0.0",
  "name": "result",
  "spec": {
    "doc": "Result type representing success or error",
    "CustomTypeSpecification": {
      "typeParams": ["ok", "err"],
      "value": {
        "constructors": {
          "ok": [["value", "ok"]],
          "err": [["error", "err"]]
        }
      }
    }
  }
}
```

### Module with Mixed Styles

**module.json** (manifest style with some inline definitions):
```json
{
  "formatVersion": "4.0.0",
  "path": "my-org/domain",
  "doc": "Domain model",
  "types": ["user", "order"],
  "values": {
    "create-user": {
      "access": "Public",
      "ExpressionBody": {
        "inputTypes": {
          "email": "morphir/sdk:string#string"
        },
        "outputType": "my-org/domain:types#user",
        "body": {
          "Constructor": {
            "attributes": {},
            "fqname": "my-org/domain:types#user",
            "args": [
              {
                "Variable": {
                  "attributes": {},
                  "name": "email"
                }
              }
            ]
          }
        }
      }
    }
  }
}
```

**Note**: While mixing styles is technically possible, it's recommended to use consistent style per module for clarity.

## Complete Examples

### Complete Module Structure

**Directory**: `.morphir-dist/pkg/my-org/my-project/domain/`

**module.json**:
```json
{
  "formatVersion": "4.0.0",
  "path": "my-org/domain",
  "doc": "Domain model for the application",
  "types": ["user", "user-(id)", "order"],
  "values": ["get-user-by-email", "create-order", "validate-user"]
}
```

**user.type.json**:
```json
{
  "formatVersion": "4.0.0",
  "name": "user",
  "doc": "Represents a user in the system",
  "def": {
    "access": "Public",
    "TypeAliasDefinition": {
      "typeParams": [],
      "typeExp": {
        "Record": {
          "fields": {
            "user-id": "my-org/domain:types#user-(id)",
            "email": "morphir/sdk:string#string",
            "created-at": "my-org/sdk:local-date-time#local-date-time"
          }
        }
      }
    }
  }
}
```

**user-(id).type.json**:
```json
{
  "formatVersion": "4.0.0",
  "name": "user-(id)",
  "def": {
    "access": "Public",
    "CustomTypeDefinition": {
      "typeParams": [],
      "access": "Public",
      "value": {
        "constructors": {
          "user-(id)": [
            ["id", "morphir/sdk:string#string"]
          ]
        }
      }
    }
  }
}
```

**get-user-by-email.value.json**:
```json
{
  "formatVersion": "4.0.0",
  "name": "get-user-by-email",
  "doc": "Retrieve a user by their email address",
  "def": {
    "access": "Public",
    "ExpressionBody": {
      "inputTypes": {
        "email": "morphir/sdk:string#string",
        "users": ["morphir/sdk:list#list", "my-org/domain:types#user"]
      },
      "outputType": ["morphir/sdk:maybe#maybe", "my-org/domain:types#user"],
      "body": {
        "Apply": {
          "attributes": {},
          "function": {
            "Reference": {
              "attributes": {},
              "fqname": "morphir/sdk:list#find",
              "args": []
            }
          },
          "argument": {
            "Variable": {
              "attributes": {},
              "name": "email"
            }
          }
        }
      }
    }
  }
}
```

## Validation Rules

### File Naming
- ✅ Must use canonical name format (kebab-case)
- ✅ Type files: `*.type.json`
- ✅ Value files: `*.value.json`
- ✅ Module files: `module.json` (exact name)
- ✅ Manifest file: `manifest.json` (exact name, at root)
- ❌ No spaces or special characters (except hyphens and parentheses)
- ❌ No uppercase letters

**Valid Examples**:
- `user.type.json` ✅
- `user-(id).type.json` ✅
- `get-user-by-email.value.json` ✅
- `value-in-(usd).value.json` ✅

**Invalid Examples**:
- `User.type.json` ❌ (uppercase)
- `user id.type.json` ❌ (space)
- `user.id.type.json` ❌ (period, use hyphen)
- `user_id.type.json` ❌ (underscore, use hyphen)

### Required Fields
- All files: `formatVersion`
- Definition files: `name`, exactly one of `def` or `spec`
- Module files: `path` or `module`
- Manifest files: `distribution`, `package`

### Field Consistency
- `name` field must match filename (without suffix)
- `path`/`module` field must match directory structure
- `def` and `spec` are mutually exclusive (exactly one required)

**Example**: If file is `user.type.json`, then `name` must be `"user"`.

**Example**: If file is in `.morphir-dist/pkg/my-org/my-project/domain/`, then `path` should be `"my-org/domain"` or `"my-org/my-project/domain"` depending on package structure.

### Type and Value Definition Validation

**Type Definitions** (`def` in `*.type.json`):
- Must contain exactly one of: `TypeAliasDefinition`, `CustomTypeDefinition`, `IncompleteTypeDefinition`
- Must include `access` field when part of PackageDefinition
- `TypeAliasDefinition` must have `typeParams` (array) and `typeExp` (type)
- `CustomTypeDefinition` must have `typeParams`, `access`, and `value.constructors` (object)
- `IncompleteTypeDefinition` must have `typeParams` and `reason` (HoleReason)

**Type Specifications** (`spec` in `*.type.json`):
- Must contain exactly one of: `TypeAliasSpecification`, `OpaqueTypeSpecification`, `CustomTypeSpecification`, `DerivedTypeSpecification`
- `OpaqueTypeSpecification` must be empty object `{}`
- `TypeAliasSpecification` must have `typeParams` and `typeExp`
- `CustomTypeSpecification` must have `typeParams` and `value.constructors`

**Value Definitions** (`def` in `*.value.json`):
- Must contain wrapper object with exactly one of: `ExpressionBody`, `NativeBody`, `ExternalBody`, `IncompleteBody`
- Must include `access` field when part of PackageDefinition
- `ExpressionBody` must have `inputTypes` (object), `outputType` (type), and `body` (expression)
- `NativeBody` must have `inputTypes`, `outputType`, and `nativeInfo`
- `ExternalBody` must have `inputTypes`, `outputType`, and `externalInfo`
- `IncompleteBody` must have `inputTypes`, `outputType`, and `reason`

**Value Specifications** (`spec` in `*.value.json`):
- Must have `inputs` (object mapping parameter names to types)
- Must have `output` (type)
- May have `doc` (string or array of strings)

### Module Manifest Validation

**Manifest Style**:
- `types` must be array of Name strings
- `values` must be array of Name strings
- Referenced type/value files must exist in same directory

**Inline Style**:
- `types` must be object mapping names to AccessControlled TypeDefinition
- `values` must be object mapping names to AccessControlled ValueDefinition
- Each definition must include `access` field

**Hybrid Style** (not recommended but allowed):
- One of `types`/`values` can be array, other can be object
- Consistency is preferred

### Distribution Manifest Validation

**Required for all distributions**:
- `formatVersion`: Must be `"4.0.0"` or `4`
- `distribution`: Must be `"Library"`, `"Specs"`, or `"Application"`
- `package`: Must be valid PackageName (canonical format)

**Required for Application distributions**:
- `entryPoints`: Must be present and non-empty object
- Each entry point must have `target` (FQName) and `kind` (EntryPointKind)

**Optional but recommended**:
- `version`: Semantic version string
- `created`: ISO 8601 timestamp
- `layout`: Should be `"VfsMode"` for document tree distributions

### Directory Structure Validation

**Package Directory**:
- Must match `package` field in `manifest.json`
- Path: `.morphir-dist/pkg/{package-path}/`

**Module Directory**:
- Must match `path`/`module` field in `module.json`
- Path: `.morphir-dist/pkg/{package-path}/{module-path}/`
- Must contain `module.json` file

**Definition Files**:
- Must be in module directory
- Filename must match `name` field in file
- Type files: `{name}.type.json`
- Value files: `{name}.value.json`

## Error Handling

### Common Validation Errors

**Missing Required Field**:
```json
// ❌ Missing 'name' field
{
  "formatVersion": "4.0.0",
  "def": { ... }
}
```

**Name Mismatch**:
```json
// ❌ File is 'user.type.json' but name is 'order'
{
  "formatVersion": "4.0.0",
  "name": "order",
  "def": { ... }
}
```

**Both def and spec Present**:
```json
// ❌ Cannot have both def and spec
{
  "formatVersion": "4.0.0",
  "name": "user",
  "def": { ... },
  "spec": { ... }
}
```

**Missing Access Field**:
```json
// ❌ Missing 'access' in def (required for PackageDefinition)
{
  "formatVersion": "4.0.0",
  "name": "user",
  "def": {
    "TypeAliasDefinition": { ... }
  }
}
```

**Invalid Entry Points**:
```json
// ❌ Application distribution missing entryPoints
{
  "formatVersion": "4.0.0",
  "distribution": "Application",
  "package": "my-org/my-cli"
  // Missing entryPoints!
}
```

### Recommended Error Messages

When validation fails, provide clear error messages:

- **File naming**: `"Filename 'User.type.json' does not match canonical name format. Expected 'user.type.json'"`
- **Name mismatch**: `"Name field 'order' does not match filename 'user.type.json'"`
- **Missing field**: `"Required field 'name' is missing in type definition file"`
- **Both def/spec**: `"Cannot have both 'def' and 'spec' fields. Use exactly one."`
- **Missing access**: `"Definition in PackageDefinition context must include 'access' field"`
- **Invalid entry points**: `"Application distribution must include 'entryPoints' field"`

## Schema Reference

Formal JSON schemas are available in:
- [morphir-ir-v4-document-tree-files.yaml](/schemas/morphir-ir-v4-document-tree-files.yaml) - Complete schemas for all file formats
- [morphir-ir-v4.yaml](/schemas/morphir-ir-v4.yaml) - Core IR schema (referenced by document tree files)

## Metadata Files

### Package Metadata

Package-level metadata can be stored in additional files:

**Location**: `.morphir-dist/pkg/package-name/package.json` (optional)

**Purpose**: Package-level metadata, dependencies, configuration

**Example**:
```json
{
  "formatVersion": "4.0.0",
  "package": "my-org/my-project",
  "version": "1.2.0",
  "description": "My project description",
  "dependencies": {
    "morphir/sdk": "3.0.0"
  },
  "metadata": {
    "author": "My Org",
    "license": "Apache-2.0",
    "repository": "https://github.com/my-org/my-project"
  }
}
```

**Note**: Package metadata files (`package.json`) are **optional** and **not part of the core V4 IR schema**. They are documented here for reference, but implementations are not required to support them. The `manifest.json` file contains all essential distribution metadata required by the V4 specification. Package metadata files may be used by tooling for additional metadata, but are not validated by the core IR schema.

### Module Metadata

Module-level metadata is stored in `module.json`. Additional metadata can be included:

**Example with extended metadata**:
```json
{
  "formatVersion": "4.0.0",
  "path": "my-org/domain",
  "doc": "Domain model",
  "types": ["user", "order"],
  "values": ["create-order"],
  "metadata": {
    "tags": ["domain", "core"],
    "deprecated": false,
    "since": "1.0.0"
  }
}
```

**Metadata Fields** (all optional):
- `tags`: Array of string tags for categorization
- `deprecated`: Boolean indicating if module is deprecated
- `since`: Version when module was introduced
- `extensions`: Object for tool-specific metadata

## File Format Comparison

### Classic Mode vs VFS Mode

| Aspect | Classic Mode | VFS Mode |
|--------|--------------|----------|
| **Structure** | Single `morphir-ir.json` file | Directory tree with individual files |
| **Manifest File** | Not separate (embedded in root) | `.morphir-dist/manifest.json` |
| **Module Structure** | Nested in distribution JSON | `module.json` file per module |
| **Type Definitions** | Nested in module JSON | `*.type.json` files |
| **Value Definitions** | Nested in module JSON | `*.value.json` files |
| **Use Case** | Simple projects, backwards compat | Large projects, incremental updates |

## Complete Directory Tree Example

```
.morphir-dist/
├── manifest.json
└── pkg/
    └── my-org/
        └── my-project/
            ├── domain/
            │   ├── module.json
            │   ├── user.type.json
            │   ├── user-(id).type.json
            │   ├── order.type.json
            │   ├── get-user-by-email.value.json
            │   └── create-order.value.json
            ├── api/
            │   ├── module.json
            │   ├── request.type.json
            │   ├── response.type.json
            │   └── handle-request.value.json
            └── utils/
                ├── module.json
                ├── validation.type.json
                └── validate-email.value.json
```

## Related Documentation

- [Module Structure](../modules.md) - Module concepts and structure
- [Distribution Structure](../../design/draft/ir/distributions.md) - Distribution modes and VFS examples
- [V4 Schema](../schemas/v4/) - Complete V4 schema documentation
- [V4 Schema YAML](../schemas/v4/morphir-ir-v4.yaml) - Formal JSON schema
