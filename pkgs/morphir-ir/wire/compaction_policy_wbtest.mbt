// Frozen policy inputs and independently written expected output from finos/morphir.
// Source: 4fa51c8b9a8634f8779e0e6b9900fc14b049da06
// docs/spec/ir/context/policy/morphir.compact-0.1.0-draft.1/cases.json

///|
test "frozen name policy: v4-single-file" {
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
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"distribution":{"Library":{"def":{"modules":{"pricing":{"access":"Public","value":{"values":{"total":{"Public":{"ExpressionBody":{"body":{"Variable":"first"},"inputTypes":{"first":{"$name":"a"},"second":{"$name":"a"}},"outputType":{"$name":"a"}}}}}}}}},"packageName":"acme/order-management"}},"formatVersion":4}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: v4-manifest" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "distribution": "Library",
    #|  "package": "acme/order-management",
    #|  "pathBudget": 4000,
    #|  "dependencies": ["morphir/SDK"]
    #|}
  let expected =
    #|{"dependencies":["morphir/SDK"],"distribution":"Library","formatVersion":4,"package":"acme/order-management","pathBudget":4000}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, false)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: v4-module" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "path": "pricing",
    #|  "values": {
    #|    "total": {
    #|      "access": "Public",
    #|      "value": {
    #|        "ExpressionBody": {
    #|          "inputTypes": { "first": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "second": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment" },
    #|          "outputType": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment",
    #|          "body": { "Variable": "first" }
    #|        }
    #|      }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"formatVersion":4,"path":"pricing","values":{"total":{"access":"Public","value":{"ExpressionBody":{"body":{"Variable":"first"},"inputTypes":{"first":{"$name":"a"},"second":{"$name":"a"}},"outputType":{"$name":"a"}}}}}}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: v4-type" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "order-total",
    #|  "def": {
    #|    "access": "Public",
    #|    "TypeAliasDefinition": {
    #|      "typeParams": [],
    #|      "typeExp": { "Record": { "fields": { "base": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "bonus": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "rebate": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment" } } }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"def":{"TypeAliasDefinition":{"typeExp":{"Record":{"fields":{"base":{"$name":"a"},"bonus":{"$name":"a"},"rebate":{"$name":"a"}}}},"typeParams":[]},"access":"Public"},"formatVersion":4,"name":"order-total"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: v4-value" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "total",
    #|  "def": {
    #|    "access": "Public",
    #|    "ExpressionBody": {
    #|      "inputTypes": { "first": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "second": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment" },
    #|      "outputType": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment",
    #|      "body": { "Variable": "first" }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"def":{"ExpressionBody":{"body":{"Variable":"first"},"inputTypes":{"first":{"$name":"a"},"second":{"$name":"a"}},"outputType":{"$name":"a"}},"access":"Public"},"formatVersion":4,"name":"total"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: v3-single-file" {
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
    #|        "inputTypes": [[["first"], {}, ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []]]],
    #|        "outputType": ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []],
    #|        "body": ["Variable", {}, ["first"]]
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
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"distribution":["Library",[["acme"],["order","management"]],[],{"modules":[[[["pricing"]],{"access":"Public","value":{"types":[],"values":[[["total"],{"access":"Public","value":{"doc":"","value":{"body":["Variable",{},["first"]],"inputTypes":[[["first"],{},["Reference",{},{"$name":"a"},[]]]],"outputType":["Reference",{},{"$name":"a"},[]]}}}]]}}]]}],"formatVersion":3}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: v3-manifest" {
  let input =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "distribution": "Library",
    #|  "package": "acme/order-management",
    #|  "pathBudget": 4000,
    #|  "dependencies": ["morphir/SDK"]
    #|}
  let expected =
    #|{"dependencies":["morphir/SDK"],"distribution":"Library","formatVersion":"3.1.0","package":"acme/order-management","pathBudget":4000}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, false)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: v3-module" {
  let input =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "path": "pricing",
    #|  "values": {
    #|    "total": {
    #|      "access": "Public",
    #|      "value": {
    #|      "doc": "",
    #|      "value": {
    #|        "inputTypes": [[["first"], {}, ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []]]],
    #|        "outputType": ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []],
    #|        "body": ["Variable", {}, ["first"]]
    #|      }
    #|    }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"formatVersion":"3.1.0","path":"pricing","values":{"total":{"access":"Public","value":{"doc":"","value":{"body":["Variable",{},["first"]],"inputTypes":[[["first"],{},["Reference",{},{"$name":"a"},[]]]],"outputType":["Reference",{},{"$name":"a"},[]]}}}}}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: v3-type" {
  let input =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "name": "order-total",
    #|  "def": {
    #|    "access": "Public",
    #|    "value": {
    #|      "doc": "",
    #|      "value": [
    #|        "TypeAliasDefinition",
    #|        [],
    #|        [
    #|          "Record",
    #|          {},
    #|          [
    #|            { "name": ["base"], "tpe": ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []] },
    #|            { "name": ["bonus"], "tpe": ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []] }
    #|          ]
    #|        ]
    #|      ]
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"def":{"access":"Public","value":{"doc":"","value":["TypeAliasDefinition",[],["Record",{},[{"name":["base"],"tpe":["Reference",{},{"$name":"a"},[]]},{"name":["bonus"],"tpe":["Reference",{},{"$name":"a"},[]]}]]]}},"formatVersion":"3.1.0","name":"order-total"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: v3-value" {
  let input =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "name": "total",
    #|  "def": {
    #|    "access": "Public",
    #|    "value": {
    #|      "doc": "",
    #|      "value": {
    #|        "inputTypes": [[["first"], {}, ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []]]],
    #|        "outputType": ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []],
    #|        "body": ["Variable", {}, ["first"]]
    #|      }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"def":{"access":"Public","value":{"doc":"","value":{"body":["Variable",{},["first"]],"inputTypes":[[["first"],{},["Reference",{},{"$name":"a"},[]]]],"outputType":["Reference",{},{"$name":"a"},[]]}}},"formatVersion":"3.1.0","name":"total"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: name-used-once" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "order-total",
    #|  "def": {
    #|    "access": "Public",
    #|    "TypeAliasDefinition": {
    #|      "typeParams": [],
    #|      "typeExp": { "Record": { "fields": { "base": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "bonus": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "loyalty": "acme/order-management:pricing/discount-rules#loyalty-discount-rate-for-premium-members", "rebate": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment" } } }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"def":{"TypeAliasDefinition":{"typeExp":{"Record":{"fields":{"base":{"$name":"a"},"bonus":{"$name":"a"},"loyalty":"acme/order-management:pricing/discount-rules#loyalty-discount-rate-for-premium-members","rebate":{"$name":"a"}}}},"typeParams":[]},"access":"Public"},"formatVersion":4,"name":"order-total"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: non-ascii-content" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "order-total",
    #|  "def": {
    #|    "access": "Public",
    #|    "doc": "Montant réduit après la taxe régionale.",
    #|    "TypeAliasDefinition": {
    #|      "typeParams": [],
    #|      "typeExp": { "Record": { "fields": { "base": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "bonus": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "rebate": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment" } } }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"def":{"TypeAliasDefinition":{"typeExp":{"Record":{"fields":{"base":{"$name":"a"},"bonus":{"$name":"a"},"rebate":{"$name":"a"}}}},"typeParams":[]},"access":"Public","doc":"Montant réduit après la taxe régionale."},"formatVersion":4,"name":"order-total"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: alias-allocation-order" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "order-total",
    #|  "def": {
    #|    "access": "Public",
    #|    "TypeAliasDefinition": {
    #|      "typeParams": [],
    #|      "typeExp": { "Record": { "fields": { "rebate": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "base": "acme/order-management:pricing/discount-rules#loyalty-discount-rate-for-premium-members", "bonus": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "extra": "acme/order-management:pricing/discount-rules#loyalty-discount-rate-for-premium-members", "fee": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "gain": "acme/order-management:pricing/discount-rules#loyalty-discount-rate-for-premium-members" } } }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#loyalty-discount-rate-for-premium-members","b":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"def":{"TypeAliasDefinition":{"typeExp":{"Record":{"fields":{"base":{"$name":"a"},"bonus":{"$name":"b"},"extra":{"$name":"a"},"fee":{"$name":"b"},"gain":{"$name":"a"},"rebate":{"$name":"b"}}}},"typeParams":[]},"access":"Public"},"formatVersion":4,"name":"order-total"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: tie" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "order-total",
    #|  "def": {
    #|    "access": "Public",
    #|    "TypeAliasDefinition": {
    #|      "typeParams": [],
    #|      "typeExp": { "Record": { "fields": { "base": "acme/orders:pricing#net-price", "bonus": "acme/orders:pricing#net-price", "rebate": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "refund": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "surcharge": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment" } } }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"def":{"TypeAliasDefinition":{"typeExp":{"Record":{"fields":{"base":"acme/orders:pricing#net-price","bonus":"acme/orders:pricing#net-price","rebate":{"$name":"a"},"refund":{"$name":"a"},"surcharge":{"$name":"a"}}}},"typeParams":[]},"access":"Public"},"formatVersion":4,"name":"order-total"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: table-order" {
  let input =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "name": "total",
    #|  "def": {
    #|    "access": "Public",
    #|    "value": {
    #|      "doc": "",
    #|      "value": {
    #|        "inputTypes": [[["discounted","amount","before","regional","sales","tax","adjustment"], {}, ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []]]],
    #|        "outputType": ["Reference", {}, [[["acme"],["order","management"]],[["pricing"],["discount","rules"]],["discounted","amount","before","regional","sales","tax","adjustment"]], []],
    #|        "body": ["Apply", {}, ["Apply", {}, ["Reference", {}, [[["morphir"],["s","d","k"]],[["basics"]],["multiply"]]], ["Variable", {}, ["discounted","amount","before","regional","sales","tax","adjustment"]]], ["Variable", {}, ["discounted","amount","before","regional","sales","tax","adjustment"]]]
    #|      }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"morphir/SDK:basics#multiply","c":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"},"names":{"b":"discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"def":{"access":"Public","value":{"doc":"","value":{"body":["Apply",{},["Apply",{},["Reference",{},{"$name":"a"}],["Variable",{},{"$name":"b"}]],["Variable",{},{"$name":"b"}]],"inputTypes":[[{"$name":"b"},{},["Reference",{},{"$name":"c"},[]]]],"outputType":["Reference",{},{"$name":"c"},[]]}}},"formatVersion":"3.1.0","name":"total"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: look-alike-literal" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "label",
    #|  "def": {
    #|    "access": "Public",
    #|    "ExpressionBody": {
    #|      "inputTypes": { "base": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "bonus": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "rebate": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment" },
    #|      "outputType": "morphir/SDK:string#string",
    #|      "body": { "Literal": { "StringLiteral": "{\"$name\":\"a\"}" } }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"def":{"ExpressionBody":{"body":{"Literal":{"StringLiteral":"{\"$name\":\"a\"}"}},"inputTypes":{"base":{"$name":"a"},"bonus":{"$name":"a"},"rebate":{"$name":"a"}},"outputType":"morphir/SDK:string#string"},"access":"Public"},"formatVersion":4,"name":"label"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: loss" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "order-total",
    #|  "def": {
    #|    "access": "Public",
    #|    "TypeAliasDefinition": {
    #|      "typeParams": [],
    #|      "typeExp": { "Record": { "fields": { "base": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment", "rebate": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment" } } }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"def":{"TypeAliasDefinition":{"typeExp":{"Record":{"fields":{"base":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment","rebate":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}}},"typeParams":[]},"access":"Public"},"formatVersion":4,"name":"order-total"}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, false)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: loss-boundary-declined" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "order-total",
    #|  "def": {
    #|    "access": "Public",
    #|    "TypeAliasDefinition": {
    #|      "typeParams": [],
    #|      "typeExp": { "Record": { "fields": { "base": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment-for-orders-shipped-to-customers-outside-the-primary-region", "rebate": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment-for-orders-shipped-to-customers-outside-the-primary-region" } } }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"def":{"TypeAliasDefinition":{"typeExp":{"Record":{"fields":{"base":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment-for-orders-shipped-to-customers-outside-the-primary-region","rebate":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment-for-orders-shipped-to-customers-outside-the-primary-region"}}},"typeParams":[]},"access":"Public"},"formatVersion":4,"name":"order-total"}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, false)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: loss-boundary-accepted" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "order-total",
    #|  "def": {
    #|    "access": "Public",
    #|    "TypeAliasDefinition": {
    #|      "typeParams": [],
    #|      "typeExp": { "Record": { "fields": { "base": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment-for-orders-shipped-to-customers-outside-the-domestic-region", "rebate": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment-for-orders-shipped-to-customers-outside-the-domestic-region" } } }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment-for-orders-shipped-to-customers-outside-the-domestic-region"}},"document":{"def":{"TypeAliasDefinition":{"typeExp":{"Record":{"fields":{"base":{"$name":"a"},"rebate":{"$name":"a"}}}},"typeParams":[]},"access":"Public"},"formatVersion":4,"name":"order-total"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: ordered-inputs" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "adjust",
    #|  "def": {
    #|    "access": "Public",
    #|    "ExpressionBody": {
    #|      "inputTypes": {
    #|        "rate": "acme/order-management:pricing/discount-rules#loyalty-discount-rate-for-premium-members",
    #|        "amount": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment",
    #|        "discount": "acme/order-management:pricing/discount-rules#loyalty-discount-rate-for-premium-members",
    #|        "limit": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"
    #|      },
    #|      "outputType": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment",
    #|      "body": { "Variable": "amount" }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#loyalty-discount-rate-for-premium-members","b":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"def":{"ExpressionBody":{"body":{"Variable":"amount"},"inputTypes":{"rate":{"$name":"a"},"amount":{"$name":"b"},"discount":{"$name":"a"},"limit":{"$name":"b"}},"outputType":{"$name":"b"}},"access":"Public"},"formatVersion":4,"name":"adjust"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "frozen name policy: exact-numbers" {
  let input =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "limits",
    #|  "def": {
    #|    "access": "Public",
    #|    "ExpressionBody": {
    #|      "inputTypes": {
    #|        "base": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment",
    #|        "bonus": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment",
    #|        "rebate": "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"
    #|      },
    #|      "outputType": { "Tuple": ["morphir/SDK:basics#int", "morphir/SDK:basics#float", "morphir/SDK:basics#float", "morphir/SDK:document#document"] },
    #|      "body": {
    #|        "Tuple": [
    #|          { "Literal": { "IntegerLiteral": 9007199254740993 } },
    #|          { "Literal": { "FloatLiteral": 1.0 } },
    #|          { "Literal": { "FloatLiteral": 1e2 } },
    #|          { "Literal": { "DocumentLiteral": { "region": "outside-primary", "cap": 1.50, "tiers": [{ "upTo": 1e3, "rate": 0.10 }] } } }
    #|        ]
    #|      }
    #|    }
    #|  }
    #|}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"def":{"ExpressionBody":{"body":{"Tuple":[{"Literal":{"IntegerLiteral":9007199254740993}},{"Literal":{"FloatLiteral":1.0}},{"Literal":{"FloatLiteral":1e2}},{"Literal":{"DocumentLiteral":{"region":"outside-primary","cap":1.50,"tiers":[{"upTo":1e3,"rate":0.10}]}}}]},"inputTypes":{"base":{"$name":"a"},"bonus":{"$name":"a"},"rebate":{"$name":"a"}},"outputType":{"Tuple":["morphir/SDK:basics#int","morphir/SDK:basics#float","morphir/SDK:basics#float","morphir/SDK:document#document"]}},"access":"Public"},"formatVersion":4,"name":"limits"}}
  let packed = compact_names(input)
  assert_eq(packed.policy, "morphir.compact/0.1.0-draft.1")
  assert_eq(packed.compacted, true)
  assert_eq(packed.written, expected)
  assert_eq(compact_names(input).written, packed.written)
  assert_eq(expand_names(packed.written), expand_names(input))
}

///|
test "whole-file expansion refuses context after document" {
  let late =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","document":{"formatVersion":4},"context":{}}
  match (Ok(expand_names(late)) catch { e => Err(e) }) {
    Err(Invalid("context.after_document", _)) => ()
    _ =>
      assert_true(
        false,
        msg="the context must precede the document in whole-file mode",
      )
  }
}

///|
test "whole-file expansion rejects duplicate aliases by their typed path" {
  let duplicate =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"names":{"a":"left","a":"right"}},"document":{"formatVersion":4}}
  match (Ok(expand_names(duplicate)) catch { e => Err(e) }) {
    Err(Invalid("context.duplicate_entry", "/context/names/a")) => ()
    _ => assert_true(false, msg="expected the duplicate alias path")
  }
}

///|
test "v4 module specification annotation names participate in compaction" {
  let input =
    #|{"formatVersion":4,"distribution":{"Specs":{"packageName":"acme/orders","spec":{"modules":{"pricing":{"annotations":[{"name":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"},{"name":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"},{"name":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}]}}}}}}
  let expected =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"fqNames":{"a":"acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"}},"document":{"distribution":{"Specs":{"packageName":"acme/orders","spec":{"modules":{"pricing":{"annotations":[{"name":{"$name":"a"}},{"name":{"$name":"a"}},{"name":{"$name":"a"}}]}}}}},"formatVersion":4}}
  assert_eq(compact_names(input).written, expected)
  assert_eq(expand_names(expected), expand_names(input))
}

///|
test "v4 constructor arrays expand typed names and keep object keys" {
  let contextual =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"names":{"a":"value-constructor"}},"document":{"formatVersion":4,"name":"order-total","spec":{"CustomTypeSpecification":{"typeParams":[],"constructors":[[{"$name":"a"},[]]]}}}}
  let expanded =
    #|{"formatVersion":4,"name":"order-total","spec":{"CustomTypeSpecification":{"constructors":[["value-constructor",[]]],"typeParams":[]}}}
  assert_eq(expand_names(contextual), expanded)
  let object_map =
    #|{"formatVersion":4,"name":"order-total","spec":{"CustomTypeSpecification":{"constructors":{"a":[]},"typeParams":[]}}}
  assert_eq(expand_names(object_map), object_map)
}

///|
test "v4 patch versions retain their exact release spelling" {
  let input =
    #|{"formatVersion":"4.0.1","package":"acme/orders","distribution":"Library"}
  let expected =
    #|{"distribution":"Library","formatVersion":"4.0.1","package":"acme/orders"}
  assert_eq(compact_names(input).written, expected)
  assert_eq(expand_names(input), expected)
}

///|
test "an alias cannot be nested in an expanded typed name" {
  let contextual =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{"names":{"a":"total"}},"document":{"formatVersion":4,"name":"order-total","def":{"access":"Public","TypeAliasDefinition":{"typeParams":[],"typeExp":{"Reference":{"fqname":["acme","pricing",{"$name":"a"}]}}}}}}
  match (Ok(expand_names(contextual)) catch { e => Err(e) }) {
    Err(Invalid("context.invalid_reference", _)) => ()
    _ =>
      assert_true(
        false,
        msg="the outer typed position must carry the complete reference",
      )
  }
}

///|
fn document_at_policy_depth(nesting : Int32) -> String {
  let ref_name = "acme/order-management:pricing/discount-rules#discounted-amount-before-regional-sales-tax-adjustment"
  let literal = "[".repeat(nesting) + "null" + "]".repeat(nesting)
  let template =
    #|{"formatVersion":4,"name":"deep","def":{"access":"Public","ExpressionBody":{"inputTypes":{"a":"@name@","b":"@name@","c":"@name@"},"outputType":"@name@","body":{"Literal":{"DocumentLiteral":@literal@}}}}}
  template
  .replace_all(old="@name@", new=ref_name)
  .replace_all(old="@literal@", new=literal)
}

///|
test "expansion admits the envelope around a maximum-depth plain document" {
  // DocumentLiteral's payload starts at depth 5 with the plain root at 0.
  let input = document_at_policy_depth(507)
  let packed = compact_names(input)
  assert_true(packed.compacted)
  let expected = expand_names(input)
  assert_eq(expand_names(packed.written), expected)
  let schema = Json::string(ContextualSchema).stringify()
  let schema_last = "{\"context\":{},\"document\":" +
    input +
    ",\"$schema\":" +
    schema +
    "}"
  assert_eq(expand_names(schema_last), expected)
}

///|
test "the envelope layer cannot make an oversized payload or plain document admissible" {
  let input = document_at_policy_depth(508)
  let template =
    #|{"$schema":"https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json","context":{},"document":@document@}
  let envelope = template.replace_all(old="@document@", new=input)
  for
    source in [
      input,
      envelope,
      "{\"document\":" + document_at_policy_depth(507) + "}",
    ] {
    match (Ok(expand_names(source)) catch { e => Err(e) }) {
      Err(Invalid("invalid_json", "Depth budget exceeded")) => ()
      _ => assert_true(false, msg="expected the existing payload depth limit")
    }
  }
}
