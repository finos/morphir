///|
/// Plain Acme orders documents from finos/morphir at 3f3157318af5fafe474a4e1b83e7e34812517f2f.
/// Source: spec/mck/bounded-generation/fixtures/acme-orders.
fn orders_v3_json() -> Array[(String, String)] {
  let sdk_add =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "name": "add",
    #|  "spec": {
    #|    "doc": "",
    #|    "value": {
    #|      "inputs": [
    #|        [["a"], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]],
    #|        [["b"], ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]]
    #|      ],
    #|      "output": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]
    #|    }
    #|  }
    #|}
    #|
  let sdk_int =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "name": "int",
    #|  "spec": { "doc": "", "value": ["OpaqueTypeSpecification", []] }
    #|}
    #|
  let sdk_basics =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "path": "basics",
    #|  "doc": "Integer operations.",
    #|  "types": ["int"],
    #|  "values": ["add"]
    #|}
    #|
  let manifest =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "distribution": "Library",
    #|  "package": "acme/orders",
    #|  "pathBudget": 4000,
    #|  "dependencies": ["morphir/SDK"]
    #|}
    #|
  let audit =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "path": "audit",
    #|  "access": "Private",
    #|  "doc": "Internal audit.",
    #|  "types": [],
    #|  "values": []
    #|}
    #|
  let domain =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "path": "domain",
    #|  "doc": "Order totals.",
    #|  "types": ["order"],
    #|  "values": ["order", "total-in-USD"]
    #|}
    #|
  let order_type =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "name": "order",
    #|  "def": {
    #|    "access": "Public",
    #|    "value": { "doc": "", "value": [
    #|      "TypeAliasDefinition",
    #|      [],
    #|      ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]
    #|    ] }
    #|  }
    #|}
    #|
  let order_value =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "name": "order",
    #|  "def": {
    #|    "access": "Public",
    #|    "value": { "doc": "", "value": {
    #|      "inputTypes": [],
    #|      "outputType": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []],
    #|      "body": ["Literal", ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], ["WholeNumberLiteral", 73]]
    #|    } }
    #|  }
    #|}
    #|
  let total =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "name": "total-in-USD",
    #|  "def": {
    #|    "access": "Public",
    #|    "value": { "doc": "", "value": {
    #|      "inputTypes": [],
    #|      "outputType": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []],
    #|      "body": ["Reference", ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []], [[["acme"], ["orders"]], [["domain"]], ["order"]]]
    #|    } }
    #|  }
    #|}
    #|
  [
    ("deps/morphir/_sdk/@/basics/add.value.json", sdk_add),
    ("deps/morphir/_sdk/@/basics/int.type.json", sdk_int),
    ("deps/morphir/_sdk/@/basics/module.json", sdk_basics),
    ("manifest.json", manifest),
    ("pkg/acme/orders/audit/module.json", audit),
    ("pkg/acme/orders/domain/module.json", domain),
    ("pkg/acme/orders/domain/order.type.json", order_type),
    ("pkg/acme/orders/domain/order.value.json", order_value),
    ("pkg/acme/orders/domain/total-in-_usd.value.json", total),
  ]
}

///|
fn orders_v3_yaml() -> Array[(String, String)] {
  let sdk_add =
    #|formatVersion: 3.1.0
    #|name: add
    #|spec:
    #|  doc: ""
    #|  value:
    #|    inputs:
    #|      - - [a]
    #|        - - Reference
    #|          - {}
    #|          - [[[morphir], [s, d, k]], [[basics]], [int]]
    #|          - []
    #|      - - [b]
    #|        - - Reference
    #|          - {}
    #|          - [[[morphir], [s, d, k]], [[basics]], [int]]
    #|          - []
    #|    output:
    #|      - Reference
    #|      - {}
    #|      - [[[morphir], [s, d, k]], [[basics]], [int]]
    #|      - []
    #|
  let sdk_int =
    #|formatVersion: 3.1.0
    #|name: int
    #|spec:
    #|  doc: ""
    #|  value: [OpaqueTypeSpecification, []]
    #|
  let sdk_basics =
    #|formatVersion: 3.1.0
    #|path: basics
    #|doc: Integer operations.
    #|types: [int]
    #|values: [add]
    #|
  let manifest =
    #|formatVersion: 3.1.0
    #|distribution: Library
    #|package: acme/orders
    #|pathBudget: 4000
    #|dependencies: [morphir/SDK]
    #|
  let audit =
    #|formatVersion: 3.1.0
    #|path: audit
    #|access: Private
    #|doc: Internal audit.
    #|types: []
    #|values: []
    #|
  let domain =
    #|formatVersion: 3.1.0
    #|path: domain
    #|doc: Order totals.
    #|types: [order]
    #|values: [order, total-in-USD]
    #|
  let order_type =
    #|formatVersion: 3.1.0
    #|name: order
    #|def:
    #|  access: Public
    #|  value:
    #|    doc: ""
    #|    value:
    #|      - TypeAliasDefinition
    #|      - []
    #|      - - Reference
    #|        - {}
    #|        - [[[morphir], [s, d, k]], [[basics]], [int]]
    #|        - []
    #|
  let order_value =
    #|formatVersion: 3.1.0
    #|name: order
    #|def:
    #|  access: Public
    #|  value:
    #|    doc: ""
    #|    value:
    #|      inputTypes: []
    #|      outputType:
    #|        - Reference
    #|        - {}
    #|        - [[[morphir], [s, d, k]], [[basics]], [int]]
    #|        - []
    #|      body:
    #|        - Literal
    #|        - - Reference
    #|          - {}
    #|          - [[[morphir], [s, d, k]], [[basics]], [int]]
    #|          - []
    #|        - [WholeNumberLiteral, 73]
    #|
  let total =
    #|formatVersion: 3.1.0
    #|name: total-in-USD
    #|def:
    #|  access: Public
    #|  value:
    #|    doc: ""
    #|    value:
    #|      inputTypes: []
    #|      outputType:
    #|        - Reference
    #|        - {}
    #|        - [[[morphir], [s, d, k]], [[basics]], [int]]
    #|        - []
    #|      body:
    #|        - Reference
    #|        - - Reference
    #|          - {}
    #|          - [[[morphir], [s, d, k]], [[basics]], [int]]
    #|          - []
    #|        - [[[acme], [orders]], [[domain]], [order]]
    #|
  [
    ("deps/morphir/_sdk/@/basics/add.value.yaml", sdk_add),
    ("deps/morphir/_sdk/@/basics/int.type.yaml", sdk_int),
    ("deps/morphir/_sdk/@/basics/module.yaml", sdk_basics),
    ("manifest.yaml", manifest),
    ("pkg/acme/orders/audit/module.yaml", audit),
    ("pkg/acme/orders/domain/module.yaml", domain),
    ("pkg/acme/orders/domain/order.type.yaml", order_type),
    ("pkg/acme/orders/domain/order.value.yaml", order_value),
    ("pkg/acme/orders/domain/total-in-_usd.value.yaml", total),
  ]
}

///|
fn orders_v4_json() -> Array[(String, String)] {
  let sdk_add =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "add",
    #|  "spec": {
    #|    "inputs": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" },
    #|    "output": "morphir/SDK:basics#int"
    #|  }
    #|}
    #|
  let sdk_int =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "int",
    #|  "spec": { "OpaqueTypeSpecification": {} }
    #|}
    #|
  let sdk_basics =
    #|{
    #|  "formatVersion": 4,
    #|  "path": "basics",
    #|  "doc": "Integer operations.",
    #|  "types": ["int"],
    #|  "values": ["add"]
    #|}
    #|
  let manifest =
    #|{
    #|  "formatVersion": 4,
    #|  "distribution": "Library",
    #|  "package": "acme/orders",
    #|  "pathBudget": 4000,
    #|  "dependencies": ["morphir/SDK"]
    #|}
    #|
  let audit =
    #|{
    #|  "formatVersion": 4,
    #|  "path": "audit",
    #|  "access": "Private",
    #|  "doc": "Internal audit.",
    #|  "types": [],
    #|  "values": []
    #|}
    #|
  let domain =
    #|{
    #|  "formatVersion": 4,
    #|  "path": "domain",
    #|  "doc": "Order totals.",
    #|  "types": ["order"],
    #|  "values": ["order", "total-in-USD"]
    #|}
    #|
  let order_type =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "order",
    #|  "def": {
    #|    "Public": {
    #|      "TypeAliasDefinition": { "typeParams": [], "typeExp": "morphir/SDK:basics#int" }
    #|    }
    #|  }
    #|}
    #|
  let order_value =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "order",
    #|  "def": {
    #|    "Public": {
    #|      "ExpressionBody": {
    #|        "inputTypes": {},
    #|        "outputType": "morphir/SDK:basics#int",
    #|        "body": { "Literal": { "IntegerLiteral": 73 } }
    #|      }
    #|    }
    #|  }
    #|}
    #|
  let total =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "total-in-USD",
    #|  "def": {
    #|    "Public": {
    #|      "ExpressionBody": {
    #|        "inputTypes": {},
    #|        "outputType": "morphir/SDK:basics#int",
    #|        "body": { "Reference": "acme/orders:domain#order" }
    #|      }
    #|    }
    #|  }
    #|}
    #|
  [
    ("deps/morphir/_sdk/@/basics/add.value.json", sdk_add),
    ("deps/morphir/_sdk/@/basics/int.type.json", sdk_int),
    ("deps/morphir/_sdk/@/basics/module.json", sdk_basics),
    ("manifest.json", manifest),
    ("pkg/acme/orders/audit/module.json", audit),
    ("pkg/acme/orders/domain/module.json", domain),
    ("pkg/acme/orders/domain/order.type.json", order_type),
    ("pkg/acme/orders/domain/order.value.json", order_value),
    ("pkg/acme/orders/domain/total-in-_usd.value.json", total),
  ]
}

///|
fn orders_v4_yaml() -> Array[(String, String)] {
  let sdk_add =
    #|formatVersion: 4
    #|name: add
    #|spec:
    #|  inputs:
    #|    a: morphir/SDK:basics#int
    #|    b: morphir/SDK:basics#int
    #|  output: morphir/SDK:basics#int
    #|
  let sdk_int =
    #|formatVersion: 4
    #|name: int
    #|spec:
    #|  OpaqueTypeSpecification: {}
    #|
  let sdk_basics =
    #|formatVersion: 4
    #|path: basics
    #|doc: Integer operations.
    #|types: [int]
    #|values: [add]
    #|
  let manifest =
    #|formatVersion: 4
    #|distribution: Library
    #|package: acme/orders
    #|pathBudget: 4000
    #|dependencies: [morphir/SDK]
    #|
  let audit =
    #|formatVersion: 4
    #|path: audit
    #|access: Private
    #|doc: Internal audit.
    #|types: []
    #|values: []
    #|
  let domain =
    #|formatVersion: 4
    #|path: domain
    #|doc: Order totals.
    #|types: [order]
    #|values: [order, total-in-USD]
    #|
  let order_type =
    #|formatVersion: 4
    #|name: order
    #|def:
    #|  Public:
    #|    TypeAliasDefinition:
    #|      typeParams: []
    #|      typeExp: morphir/SDK:basics#int
    #|
  let order_value =
    #|formatVersion: 4
    #|name: order
    #|def:
    #|  Public:
    #|    ExpressionBody:
    #|      inputTypes: {}
    #|      outputType: morphir/SDK:basics#int
    #|      body:
    #|        Literal:
    #|          IntegerLiteral: 73
    #|
  let total =
    #|formatVersion: 4
    #|name: total-in-USD
    #|def:
    #|  Public:
    #|    ExpressionBody:
    #|      inputTypes: {}
    #|      outputType: morphir/SDK:basics#int
    #|      body:
    #|        Reference: acme/orders:domain#order
    #|
  [
    ("deps/morphir/_sdk/@/basics/add.value.yaml", sdk_add),
    ("deps/morphir/_sdk/@/basics/int.type.yaml", sdk_int),
    ("deps/morphir/_sdk/@/basics/module.yaml", sdk_basics),
    ("manifest.yaml", manifest),
    ("pkg/acme/orders/audit/module.yaml", audit),
    ("pkg/acme/orders/domain/module.yaml", domain),
    ("pkg/acme/orders/domain/order.type.yaml", order_type),
    ("pkg/acme/orders/domain/order.value.yaml", order_value),
    ("pkg/acme/orders/domain/total-in-_usd.value.yaml", total),
  ]
}
