---
id: json-schema-sample
---

# Json Schema Sample
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://example.com/types.schema.json",
  "$defs": {
    "Morphir.Reference.Model.Types.Quantity": {
      "type": "integer"
    },
    "Cart": {
      "type": "array",
      "items": {
        "type": "object",
        "properties": {
          "title": {
            "type": "string"
          },
          "productQuantity": {
            "$ref": "#/defs/Quantity"
          }
        }
      }
    },
    "Int": {
      "type": "integer"
    },
    "Custom.CustomNoArg": {
      "const": "CustomNoArg"
    },
    "Custom.CustomOneArg": {
      "type": "array",
      "items": false,
      "prefixItems": [
        {
          "const": "CustomOneArg"
        },
        {
          "type": "boolean"
        }
      ]
    },
    "Custom.CustomTwoArg": {
      "type": "array",
      "items": false,
      "prefixItems": [
        {
          "const": "CustomTwoArg"
        },
        {
          "type": "string"
        },
        {
          "$ref": "#/defs/Quantity"
        }
      ]
    },
    "FirstName": {
      "type": "array",
      "items": false,
      "prefixItems": [
        {
          "const": "FirstName"
        },
        {
          "type": "string"
        }
      ]
    },
    "Maybe.Just": {
      "type": "array",
      "items": false,
      "prefixItems": [
        {
          "type": {}
        },
        {
          "type": "null"
        }
      ]
    }
  }
}
```