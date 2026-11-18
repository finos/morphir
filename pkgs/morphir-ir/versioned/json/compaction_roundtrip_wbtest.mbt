// Based on the single-file policy inputs at Morphir 4fa51c8b9a8634f8779e0e6b9900fc14b049da06.
// The classic fixture supplies inferred types in the input and body attribute slots

///|
test "classic inferred attributes stay typed-equal after compaction and expansion" {
  let input =
    #|{
    #|  "formatVersion": 3,
    #|  "distribution": [
    #|    "Library",
    #|    [["acme"], ["order", "management"]],
    #|    [],
    #|    {
    #|      "modules": [
    #|        [
    #|          [["pricing"]],
    #|          {
    #|            "access": "Public",
    #|            "value": {
    #|              "types": [],
    #|              "values": [
    #|                [["total"], { "access": "Public", "value": {
    #|      "doc": "",
    #|      "value": {
    #|        "inputTypes": [[["first"], ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []], ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []]]],
    #|        "outputType": ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []],
    #|        "body": ["Variable", ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []], ["first"]]
    #|      }
    #|    } }]
    #|              ]
    #|            }
    #|          }
    #|        ]
    #|      ]
    #|    }
    #|  ]
    #|}
  let packed = @wire.compact_names(input)
  assert_true(packed.compacted)
  assert_eq(read(@wire.expand_names(packed.written)), read(input))
}

///|
test "frozen v4-single-file stays typed-equal after compaction and expansion" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "distribution": {
    #|    "Library": {
    #|      "packageName": "acme/order-management",
    #|      "def": {
    #|        "modules": {
    #|          "pricing": {
    #|            "access": "Public",
    #|            "value": {
    #|              "values": {
    #|                "total": {
    #|                  "Public": {
    #|                    "ExpressionBody": {
    #|                      "inputTypes": { "first": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "second": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment" },
    #|                      "outputType": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment",
    #|                      "body": { "Variable": "first" }
    #|                    }
    #|                  }
    #|                }
    #|              }
    #|            }
    #|          }
    #|        }
    #|      }
    #|    }
    #|  }
    #|}
  let packed = @wire.compact_names(input)
  assert_true(packed.compacted)
  assert_eq(read(@wire.expand_names(packed.written)), read(input))
}
