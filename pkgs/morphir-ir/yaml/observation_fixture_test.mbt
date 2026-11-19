// Frozen independent parent inputs and expectations. Do not regenerate from a reader.
// finos/morphir 3652032a53adeb6bfa4a5d672142487de45c57c5
// spec/mck/bounded-generation/fixtures/acme-orders

///|
fn observation_expected() -> Json raise {
  let text =
    #|{
    #|  "distribution": "Library",
    #|  "package": "acme/orders",
    #|  "pathBudget": 4000,
    #|  "dependencies": ["morphir/SDK"],
    #|  "modules": [
    #|    {
    #|      "package": "acme/orders",
    #|      "path": "audit",
    #|      "role": "definition",
    #|      "access": "Private",
    #|      "document": "pkg/acme/orders/audit/module",
    #|      "members": []
    #|    },
    #|    {
    #|      "package": "acme/orders",
    #|      "path": "domain",
    #|      "role": "definition",
    #|      "access": "Public",
    #|      "document": "pkg/acme/orders/domain/module",
    #|      "members": [
    #|        { "name": "order", "kind": "type", "role": "definition", "document": "pkg/acme/orders/domain/order.type" },
    #|        { "name": "order", "kind": "value", "role": "definition", "document": "pkg/acme/orders/domain/order.value" },
    #|        { "name": "total-in-USD", "kind": "value", "role": "definition", "document": "pkg/acme/orders/domain/total-in-_usd.value" }
    #|      ]
    #|    },
    #|    {
    #|      "package": "morphir/SDK",
    #|      "path": "basics",
    #|      "role": "specification",
    #|      "document": "deps/morphir/_sdk/@/basics/module",
    #|      "members": [
    #|        { "name": "int", "kind": "type", "role": "specification", "document": "deps/morphir/_sdk/@/basics/int.type" },
    #|        { "name": "add", "kind": "value", "role": "specification", "document": "deps/morphir/_sdk/@/basics/add.value" }
    #|      ]
    #|    }
    #|  ],
    #|  "domainInventory": {
    #|    "pageSize": 2,
    #|    "pages": [
    #|      ["pkg/acme/orders/domain/order.type", "pkg/acme/orders/domain/order.value"],
    #|      ["pkg/acme/orders/domain/total-in-_usd.value"]
    #|    ],
    #|    "finalPageBody": {
    #|      "document": "pkg/acme/orders/domain/total-in-_usd.value",
    #|      "outputType": "morphir/SDK:basics#int",
    #|      "reference": "acme/orders:domain#order",
    #|      "referenceKind": "value",
    #|      "referencedIntegerLiteral": 73
    #|    }
    #|  },
    #|  "classicAttributes": [
    #|    { "document": "pkg/acme/orders/domain/order.type", "pointer": "/def/value/value/2/1", "value": {} },
    #|    { "document": "pkg/acme/orders/domain/order.value", "pointer": "/def/value/value/outputType/1", "value": {} },
    #|    {
    #|      "document": "pkg/acme/orders/domain/order.value",
    #|      "pointer": "/def/value/value/body/1",
    #|      "value": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]
    #|    },
    #|    { "document": "pkg/acme/orders/domain/total-in-_usd.value", "pointer": "/def/value/value/outputType/1", "value": {} },
    #|    {
    #|      "document": "pkg/acme/orders/domain/total-in-_usd.value",
    #|      "pointer": "/def/value/value/body/1",
    #|      "value": ["Reference", {}, [[["morphir"], ["s", "d", "k"]], [["basics"]], ["int"]], []]
    #|    },
    #|    { "document": "deps/morphir/_sdk/@/basics/add.value", "pointer": "/spec/value/inputs/0/1/1", "value": {} },
    #|    { "document": "deps/morphir/_sdk/@/basics/add.value", "pointer": "/spec/value/inputs/1/1/1", "value": {} },
    #|    { "document": "deps/morphir/_sdk/@/basics/add.value", "pointer": "/spec/value/output/1", "value": {} }
    #|  ]
    #|}
    #|
  @wire.parse(text)
}

///|
fn frozen_v3_1_plain_json() -> Array[(String, String)] {
  let file_0 =
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
  let file_1 =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "name": "int",
    #|  "spec": { "doc": "", "value": ["OpaqueTypeSpecification", []] }
    #|}
    #|
  let file_2 =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "path": "basics",
    #|  "doc": "Integer operations.",
    #|  "types": ["int"],
    #|  "values": ["add"]
    #|}
    #|
  let file_3 =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "distribution": "Library",
    #|  "package": "acme/orders",
    #|  "pathBudget": 4000,
    #|  "dependencies": ["morphir/SDK"]
    #|}
    #|
  let file_4 =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "path": "audit",
    #|  "access": "Private",
    #|  "doc": "Internal audit.",
    #|  "types": [],
    #|  "values": []
    #|}
    #|
  let file_5 =
    #|{
    #|  "formatVersion": "3.1.0",
    #|  "path": "domain",
    #|  "doc": "Order totals.",
    #|  "types": ["order"],
    #|  "values": ["order", "total-in-USD"]
    #|}
    #|
  let file_6 =
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
  let file_7 =
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
  let file_8 =
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
    ("deps/morphir/_sdk/@/basics/add.value.json", file_0),
    ("deps/morphir/_sdk/@/basics/int.type.json", file_1),
    ("deps/morphir/_sdk/@/basics/module.json", file_2),
    ("manifest.json", file_3),
    ("pkg/acme/orders/audit/module.json", file_4),
    ("pkg/acme/orders/domain/module.json", file_5),
    ("pkg/acme/orders/domain/order.type.json", file_6),
    ("pkg/acme/orders/domain/order.value.json", file_7),
    ("pkg/acme/orders/domain/total-in-_usd.value.json", file_8),
  ]
}

///|
fn frozen_v3_1_plain_yaml() -> Array[(String, String)] {
  let file_0 =
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
  let file_1 =
    #|formatVersion: 3.1.0
    #|name: int
    #|spec:
    #|  doc: ""
    #|  value: [OpaqueTypeSpecification, []]
    #|
  let file_2 =
    #|formatVersion: 3.1.0
    #|path: basics
    #|doc: Integer operations.
    #|types: [int]
    #|values: [add]
    #|
  let file_3 =
    #|formatVersion: 3.1.0
    #|distribution: Library
    #|package: acme/orders
    #|pathBudget: 4000
    #|dependencies: [morphir/SDK]
    #|
  let file_4 =
    #|formatVersion: 3.1.0
    #|path: audit
    #|access: Private
    #|doc: Internal audit.
    #|types: []
    #|values: []
    #|
  let file_5 =
    #|formatVersion: 3.1.0
    #|path: domain
    #|doc: Order totals.
    #|types: [order]
    #|values: [order, total-in-USD]
    #|
  let file_6 =
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
  let file_7 =
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
  let file_8 =
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
    ("deps/morphir/_sdk/@/basics/add.value.yaml", file_0),
    ("deps/morphir/_sdk/@/basics/int.type.yaml", file_1),
    ("deps/morphir/_sdk/@/basics/module.yaml", file_2),
    ("manifest.yaml", file_3),
    ("pkg/acme/orders/audit/module.yaml", file_4),
    ("pkg/acme/orders/domain/module.yaml", file_5),
    ("pkg/acme/orders/domain/order.type.yaml", file_6),
    ("pkg/acme/orders/domain/order.value.yaml", file_7),
    ("pkg/acme/orders/domain/total-in-_usd.value.yaml", file_8),
  ]
}

///|
fn frozen_v3_1_contextual_json() -> Array[(String, String)] {
  let file_0 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "names": { "n": "add" },
    #|    "fqNames": { "i": "morphir/SDK:basics#int" }
    #|  },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "name": { "$name": "n" },
    #|    "spec": {
    #|      "doc": "",
    #|      "value": {
    #|        "inputs": [
    #|          [["a"], ["Reference", {}, { "$name": "i" }, []]],
    #|          [["b"], ["Reference", {}, { "$name": "i" }, []]]
    #|        ],
    #|        "output": ["Reference", {}, { "$name": "i" }, []]
    #|      }
    #|    }
    #|  }
    #|}
    #|
  let file_1 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": { "names": { "n": "int" } },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "name": { "$name": "n" },
    #|    "spec": { "doc": "", "value": ["OpaqueTypeSpecification", []] }
    #|  }
    #|}
    #|
  let file_2 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "modulePaths": { "m": "basics" },
    #|    "names": { "i": "int", "a": "add" }
    #|  },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "path": { "$name": "m" },
    #|    "doc": "Integer operations.",
    #|    "types": [{ "$name": "i" }],
    #|    "values": [{ "$name": "a" }]
    #|  }
    #|}
    #|
  let file_3 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": { "packagePaths": { "p": "acme/orders", "d": "morphir/SDK" } },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "distribution": "Library",
    #|    "package": { "$name": "p" },
    #|    "pathBudget": 4000,
    #|    "dependencies": [{ "$name": "d" }]
    #|  }
    #|}
    #|
  let file_4 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": { "modulePaths": { "m": "audit" } },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "path": { "$name": "m" },
    #|    "access": "Private",
    #|    "doc": "Internal audit.",
    #|    "types": [],
    #|    "values": []
    #|  }
    #|}
    #|
  let file_5 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "modulePaths": { "m": "domain" },
    #|    "names": { "o": "order", "t": "total-in-USD" }
    #|  },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "path": { "$name": "m" },
    #|    "doc": "Order totals.",
    #|    "types": [{ "$name": "o" }],
    #|    "values": [{ "$name": "o" }, { "$name": "t" }]
    #|  }
    #|}
    #|
  let file_6 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "names": { "n": "order" },
    #|    "fqNames": { "i": "morphir/SDK:basics#int" }
    #|  },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "name": { "$name": "n" },
    #|    "def": {
    #|      "access": "Public",
    #|      "value": { "doc": "", "value": [
    #|        "TypeAliasDefinition",
    #|        [],
    #|        ["Reference", {}, { "$name": "i" }, []]
    #|      ] }
    #|    }
    #|  }
    #|}
    #|
  let file_7 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "names": { "n": "order" },
    #|    "fqNames": { "i": "morphir/SDK:basics#int" }
    #|  },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "name": { "$name": "n" },
    #|    "def": {
    #|      "access": "Public",
    #|      "value": { "doc": "", "value": {
    #|        "inputTypes": [],
    #|        "outputType": ["Reference", {}, { "$name": "i" }, []],
    #|        "body": ["Literal", ["Reference", {}, { "$name": "i" }, []], ["WholeNumberLiteral", 73]]
    #|      } }
    #|    }
    #|  }
    #|}
    #|
  let file_8 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "names": { "n": "total-in-USD" },
    #|    "fqNames": { "i": "morphir/SDK:basics#int", "o": "acme/orders:domain#order" }
    #|  },
    #|  "document": {
    #|    "formatVersion": "3.1.0",
    #|    "name": { "$name": "n" },
    #|    "def": {
    #|      "access": "Public",
    #|      "value": { "doc": "", "value": {
    #|        "inputTypes": [],
    #|        "outputType": ["Reference", {}, { "$name": "i" }, []],
    #|        "body": ["Reference", ["Reference", {}, { "$name": "i" }, []], { "$name": "o" }]
    #|      } }
    #|    }
    #|  }
    #|}
    #|
  [
    ("deps/morphir/_sdk/@/basics/add.value.json", file_0),
    ("deps/morphir/_sdk/@/basics/int.type.json", file_1),
    ("deps/morphir/_sdk/@/basics/module.json", file_2),
    ("manifest.json", file_3),
    ("pkg/acme/orders/audit/module.json", file_4),
    ("pkg/acme/orders/domain/module.json", file_5),
    ("pkg/acme/orders/domain/order.type.json", file_6),
    ("pkg/acme/orders/domain/order.value.json", file_7),
    ("pkg/acme/orders/domain/total-in-_usd.value.json", file_8),
  ]
}

///|
fn frozen_v3_1_contextual_yaml() -> Array[(String, String)] {
  let file_0 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": add
    #|  fqNames:
    #|    i: "morphir/SDK:basics#int"
    #|document:
    #|  formatVersion: 3.1.0
    #|  name:
    #|    $name: "n"
    #|  spec:
    #|    doc: ""
    #|    value:
    #|      inputs:
    #|        - - - a
    #|          - - Reference
    #|            - {}
    #|            - $name: i
    #|            - []
    #|        - - - b
    #|          - - Reference
    #|            - {}
    #|            - $name: i
    #|            - []
    #|      output:
    #|        - Reference
    #|        - {}
    #|        - $name: i
    #|        - []
    #|
  let file_1 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": int
    #|document:
    #|  formatVersion: 3.1.0
    #|  name:
    #|    $name: "n"
    #|  spec:
    #|    doc: ""
    #|    value:
    #|      - OpaqueTypeSpecification
    #|      - []
    #|
  let file_2 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  modulePaths:
    #|    m: basics
    #|  names:
    #|    i: int
    #|    a: add
    #|document:
    #|  formatVersion: 3.1.0
    #|  path:
    #|    $name: m
    #|  doc: Integer operations.
    #|  types:
    #|    - $name: i
    #|  values:
    #|    - $name: a
    #|
  let file_3 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  packagePaths:
    #|    p: acme/orders
    #|    d: morphir/SDK
    #|document:
    #|  formatVersion: 3.1.0
    #|  distribution: Library
    #|  package:
    #|    $name: p
    #|  pathBudget: 4000
    #|  dependencies:
    #|    - $name: d
    #|
  let file_4 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  modulePaths:
    #|    m: audit
    #|document:
    #|  formatVersion: 3.1.0
    #|  path:
    #|    $name: m
    #|  access: Private
    #|  doc: Internal audit.
    #|  types:
    #|    []
    #|  values:
    #|    []
    #|
  let file_5 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  modulePaths:
    #|    m: domain
    #|  names:
    #|    o: order
    #|    t: total-in-USD
    #|document:
    #|  formatVersion: 3.1.0
    #|  path:
    #|    $name: m
    #|  doc: Order totals.
    #|  types:
    #|    - $name: o
    #|  values:
    #|    - $name: o
    #|    - $name: t
    #|
  let file_6 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": order
    #|  fqNames:
    #|    i: "morphir/SDK:basics#int"
    #|document:
    #|  formatVersion: 3.1.0
    #|  name:
    #|    $name: "n"
    #|  def:
    #|    access: Public
    #|    value:
    #|      doc: ""
    #|      value:
    #|        - TypeAliasDefinition
    #|        - []
    #|        - - Reference
    #|          - {}
    #|          - $name: i
    #|          - []
    #|
  let file_7 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": order
    #|  fqNames:
    #|    i: "morphir/SDK:basics#int"
    #|document:
    #|  formatVersion: 3.1.0
    #|  name:
    #|    $name: "n"
    #|  def:
    #|    access: Public
    #|    value:
    #|      doc: ""
    #|      value:
    #|        inputTypes:
    #|          []
    #|        outputType:
    #|          - Reference
    #|          - {}
    #|          - $name: i
    #|          - []
    #|        body:
    #|          - Literal
    #|          - - Reference
    #|            - {}
    #|            - $name: i
    #|            - []
    #|          - - WholeNumberLiteral
    #|            - 73
    #|
  let file_8 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": total-in-USD
    #|  fqNames:
    #|    i: "morphir/SDK:basics#int"
    #|    o: "acme/orders:domain#order"
    #|document:
    #|  formatVersion: 3.1.0
    #|  name:
    #|    $name: "n"
    #|  def:
    #|    access: Public
    #|    value:
    #|      doc: ""
    #|      value:
    #|        inputTypes:
    #|          []
    #|        outputType:
    #|          - Reference
    #|          - {}
    #|          - $name: i
    #|          - []
    #|        body:
    #|          - Reference
    #|          - - Reference
    #|            - {}
    #|            - $name: i
    #|            - []
    #|          - $name: o
    #|
  [
    ("deps/morphir/_sdk/@/basics/add.value.yaml", file_0),
    ("deps/morphir/_sdk/@/basics/int.type.yaml", file_1),
    ("deps/morphir/_sdk/@/basics/module.yaml", file_2),
    ("manifest.yaml", file_3),
    ("pkg/acme/orders/audit/module.yaml", file_4),
    ("pkg/acme/orders/domain/module.yaml", file_5),
    ("pkg/acme/orders/domain/order.type.yaml", file_6),
    ("pkg/acme/orders/domain/order.value.yaml", file_7),
    ("pkg/acme/orders/domain/total-in-_usd.value.yaml", file_8),
  ]
}

///|
fn frozen_v4_plain_json() -> Array[(String, String)] {
  let file_0 =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "add",
    #|  "spec": {
    #|    "inputs": { "a": "morphir/SDK:basics#int", "b": "morphir/SDK:basics#int" },
    #|    "output": "morphir/SDK:basics#int"
    #|  }
    #|}
    #|
  let file_1 =
    #|{
    #|  "formatVersion": 4,
    #|  "name": "int",
    #|  "spec": { "OpaqueTypeSpecification": {} }
    #|}
    #|
  let file_2 =
    #|{
    #|  "formatVersion": 4,
    #|  "path": "basics",
    #|  "doc": "Integer operations.",
    #|  "types": ["int"],
    #|  "values": ["add"]
    #|}
    #|
  let file_3 =
    #|{
    #|  "formatVersion": 4,
    #|  "distribution": "Library",
    #|  "package": "acme/orders",
    #|  "pathBudget": 4000,
    #|  "dependencies": ["morphir/SDK"]
    #|}
    #|
  let file_4 =
    #|{
    #|  "formatVersion": 4,
    #|  "path": "audit",
    #|  "access": "Private",
    #|  "doc": "Internal audit.",
    #|  "types": [],
    #|  "values": []
    #|}
    #|
  let file_5 =
    #|{
    #|  "formatVersion": 4,
    #|  "path": "domain",
    #|  "doc": "Order totals.",
    #|  "types": ["order"],
    #|  "values": ["order", "total-in-USD"]
    #|}
    #|
  let file_6 =
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
  let file_7 =
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
  let file_8 =
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
    ("deps/morphir/_sdk/@/basics/add.value.json", file_0),
    ("deps/morphir/_sdk/@/basics/int.type.json", file_1),
    ("deps/morphir/_sdk/@/basics/module.json", file_2),
    ("manifest.json", file_3),
    ("pkg/acme/orders/audit/module.json", file_4),
    ("pkg/acme/orders/domain/module.json", file_5),
    ("pkg/acme/orders/domain/order.type.json", file_6),
    ("pkg/acme/orders/domain/order.value.json", file_7),
    ("pkg/acme/orders/domain/total-in-_usd.value.json", file_8),
  ]
}

///|
fn frozen_v4_plain_yaml() -> Array[(String, String)] {
  let file_0 =
    #|formatVersion: 4
    #|name: add
    #|spec:
    #|  inputs:
    #|    a: morphir/SDK:basics#int
    #|    b: morphir/SDK:basics#int
    #|  output: morphir/SDK:basics#int
    #|
  let file_1 =
    #|formatVersion: 4
    #|name: int
    #|spec:
    #|  OpaqueTypeSpecification: {}
    #|
  let file_2 =
    #|formatVersion: 4
    #|path: basics
    #|doc: Integer operations.
    #|types: [int]
    #|values: [add]
    #|
  let file_3 =
    #|formatVersion: 4
    #|distribution: Library
    #|package: acme/orders
    #|pathBudget: 4000
    #|dependencies: [morphir/SDK]
    #|
  let file_4 =
    #|formatVersion: 4
    #|path: audit
    #|access: Private
    #|doc: Internal audit.
    #|types: []
    #|values: []
    #|
  let file_5 =
    #|formatVersion: 4
    #|path: domain
    #|doc: Order totals.
    #|types: [order]
    #|values: [order, total-in-USD]
    #|
  let file_6 =
    #|formatVersion: 4
    #|name: order
    #|def:
    #|  Public:
    #|    TypeAliasDefinition:
    #|      typeParams: []
    #|      typeExp: morphir/SDK:basics#int
    #|
  let file_7 =
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
  let file_8 =
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
    ("deps/morphir/_sdk/@/basics/add.value.yaml", file_0),
    ("deps/morphir/_sdk/@/basics/int.type.yaml", file_1),
    ("deps/morphir/_sdk/@/basics/module.yaml", file_2),
    ("manifest.yaml", file_3),
    ("pkg/acme/orders/audit/module.yaml", file_4),
    ("pkg/acme/orders/domain/module.yaml", file_5),
    ("pkg/acme/orders/domain/order.type.yaml", file_6),
    ("pkg/acme/orders/domain/order.value.yaml", file_7),
    ("pkg/acme/orders/domain/total-in-_usd.value.yaml", file_8),
  ]
}

///|
fn frozen_v4_contextual_json() -> Array[(String, String)] {
  let file_0 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "names": { "n": "add" },
    #|    "fqNames": { "i": "morphir/SDK:basics#int" }
    #|  },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "name": { "$name": "n" },
    #|    "spec": {
    #|      "inputs": { "a": { "$name": "i" }, "b": { "$name": "i" } },
    #|      "output": { "$name": "i" }
    #|    }
    #|  }
    #|}
    #|
  let file_1 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": { "names": { "n": "int" } },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "name": { "$name": "n" },
    #|    "spec": { "OpaqueTypeSpecification": {} }
    #|  }
    #|}
    #|
  let file_2 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "modulePaths": { "m": "basics" },
    #|    "names": { "i": "int", "a": "add" }
    #|  },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "path": { "$name": "m" },
    #|    "doc": "Integer operations.",
    #|    "types": [{ "$name": "i" }],
    #|    "values": [{ "$name": "a" }]
    #|  }
    #|}
    #|
  let file_3 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": { "packagePaths": { "p": "acme/orders", "d": "morphir/SDK" } },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "distribution": "Library",
    #|    "package": { "$name": "p" },
    #|    "pathBudget": 4000,
    #|    "dependencies": [{ "$name": "d" }]
    #|  }
    #|}
    #|
  let file_4 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": { "modulePaths": { "m": "audit" } },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "path": { "$name": "m" },
    #|    "access": "Private",
    #|    "doc": "Internal audit.",
    #|    "types": [],
    #|    "values": []
    #|  }
    #|}
    #|
  let file_5 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "modulePaths": { "m": "domain" },
    #|    "names": { "o": "order", "t": "total-in-USD" }
    #|  },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "path": { "$name": "m" },
    #|    "doc": "Order totals.",
    #|    "types": [{ "$name": "o" }],
    #|    "values": [{ "$name": "o" }, { "$name": "t" }]
    #|  }
    #|}
    #|
  let file_6 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "names": { "n": "order" },
    #|    "fqNames": { "i": "morphir/SDK:basics#int" }
    #|  },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "name": { "$name": "n" },
    #|    "def": {
    #|      "Public": {
    #|        "TypeAliasDefinition": { "typeParams": [], "typeExp": { "$name": "i" } }
    #|      }
    #|    }
    #|  }
    #|}
    #|
  let file_7 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "names": { "n": "order" },
    #|    "fqNames": { "i": "morphir/SDK:basics#int" }
    #|  },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "name": { "$name": "n" },
    #|    "def": {
    #|      "Public": {
    #|        "ExpressionBody": {
    #|          "inputTypes": {},
    #|          "outputType": { "$name": "i" },
    #|          "body": { "Literal": { "IntegerLiteral": 73 } }
    #|        }
    #|      }
    #|    }
    #|  }
    #|}
    #|
  let file_8 =
    #|{
    #|  "$schema": "https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json",
    #|  "context": {
    #|    "names": { "n": "total-in-USD" },
    #|    "fqNames": { "i": "morphir/SDK:basics#int", "o": "acme/orders:domain#order" }
    #|  },
    #|  "document": {
    #|    "formatVersion": 4,
    #|    "name": { "$name": "n" },
    #|    "def": {
    #|      "Public": {
    #|        "ExpressionBody": {
    #|          "inputTypes": {},
    #|          "outputType": { "$name": "i" },
    #|          "body": { "Reference": { "$name": "o" } }
    #|        }
    #|      }
    #|    }
    #|  }
    #|}
    #|
  [
    ("deps/morphir/_sdk/@/basics/add.value.json", file_0),
    ("deps/morphir/_sdk/@/basics/int.type.json", file_1),
    ("deps/morphir/_sdk/@/basics/module.json", file_2),
    ("manifest.json", file_3),
    ("pkg/acme/orders/audit/module.json", file_4),
    ("pkg/acme/orders/domain/module.json", file_5),
    ("pkg/acme/orders/domain/order.type.json", file_6),
    ("pkg/acme/orders/domain/order.value.json", file_7),
    ("pkg/acme/orders/domain/total-in-_usd.value.json", file_8),
  ]
}

///|
fn frozen_v4_contextual_yaml() -> Array[(String, String)] {
  let file_0 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": add
    #|  fqNames:
    #|    i: "morphir/SDK:basics#int"
    #|document:
    #|  formatVersion: 4
    #|  name:
    #|    $name: "n"
    #|  spec:
    #|    inputs:
    #|      a:
    #|        $name: i
    #|      b:
    #|        $name: i
    #|    output:
    #|      $name: i
    #|
  let file_1 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": int
    #|document:
    #|  formatVersion: 4
    #|  name:
    #|    $name: "n"
    #|  spec:
    #|    OpaqueTypeSpecification:
    #|      {}
    #|
  let file_2 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  modulePaths:
    #|    m: basics
    #|  names:
    #|    i: int
    #|    a: add
    #|document:
    #|  formatVersion: 4
    #|  path:
    #|    $name: m
    #|  doc: Integer operations.
    #|  types:
    #|    - $name: i
    #|  values:
    #|    - $name: a
    #|
  let file_3 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  packagePaths:
    #|    p: acme/orders
    #|    d: morphir/SDK
    #|document:
    #|  formatVersion: 4
    #|  distribution: Library
    #|  package:
    #|    $name: p
    #|  pathBudget: 4000
    #|  dependencies:
    #|    - $name: d
    #|
  let file_4 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  modulePaths:
    #|    m: audit
    #|document:
    #|  formatVersion: 4
    #|  path:
    #|    $name: m
    #|  access: Private
    #|  doc: Internal audit.
    #|  types:
    #|    []
    #|  values:
    #|    []
    #|
  let file_5 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  modulePaths:
    #|    m: domain
    #|  names:
    #|    o: order
    #|    t: total-in-USD
    #|document:
    #|  formatVersion: 4
    #|  path:
    #|    $name: m
    #|  doc: Order totals.
    #|  types:
    #|    - $name: o
    #|  values:
    #|    - $name: o
    #|    - $name: t
    #|
  let file_6 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": order
    #|  fqNames:
    #|    i: "morphir/SDK:basics#int"
    #|document:
    #|  formatVersion: 4
    #|  name:
    #|    $name: "n"
    #|  def:
    #|    Public:
    #|      TypeAliasDefinition:
    #|        typeParams:
    #|          []
    #|        typeExp:
    #|          $name: i
    #|
  let file_7 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": order
    #|  fqNames:
    #|    i: "morphir/SDK:basics#int"
    #|document:
    #|  formatVersion: 4
    #|  name:
    #|    $name: "n"
    #|  def:
    #|    Public:
    #|      ExpressionBody:
    #|        inputTypes:
    #|          {}
    #|        outputType:
    #|          $name: i
    #|        body:
    #|          Literal:
    #|            IntegerLiteral: 73
    #|
  let file_8 =
    #|$schema: https://morphir.finos.org/schemas/ir-context/0.1.0-draft.1/document.schema.json
    #|context:
    #|  names:
    #|    "n": total-in-USD
    #|  fqNames:
    #|    i: "morphir/SDK:basics#int"
    #|    o: "acme/orders:domain#order"
    #|document:
    #|  formatVersion: 4
    #|  name:
    #|    $name: "n"
    #|  def:
    #|    Public:
    #|      ExpressionBody:
    #|        inputTypes:
    #|          {}
    #|        outputType:
    #|          $name: i
    #|        body:
    #|          Reference:
    #|            $name: o
    #|
  [
    ("deps/morphir/_sdk/@/basics/add.value.yaml", file_0),
    ("deps/morphir/_sdk/@/basics/int.type.yaml", file_1),
    ("deps/morphir/_sdk/@/basics/module.yaml", file_2),
    ("manifest.yaml", file_3),
    ("pkg/acme/orders/audit/module.yaml", file_4),
    ("pkg/acme/orders/domain/module.yaml", file_5),
    ("pkg/acme/orders/domain/order.type.yaml", file_6),
    ("pkg/acme/orders/domain/order.value.yaml", file_7),
    ("pkg/acme/orders/domain/total-in-_usd.value.yaml", file_8),
  ]
}

///|
fn observation_profiles() -> Array[
  (String, Array[(String, String)], @yaml.TreeEncoding),
] {
  [
    ("v3.1/plain-json", frozen_v3_1_plain_json(), @yaml.Plain),
    ("v3.1/plain-yaml", frozen_v3_1_plain_yaml(), @yaml.Plain),
    (
      "v3.1/contextual-json",
      frozen_v3_1_contextual_json(),
      @yaml.ContextualDraft1,
    ),
    (
      "v3.1/contextual-yaml",
      frozen_v3_1_contextual_yaml(),
      @yaml.ContextualDraft1,
    ),
    ("v4/plain-json", frozen_v4_plain_json(), @yaml.Plain),
    ("v4/plain-yaml", frozen_v4_plain_yaml(), @yaml.Plain),
    ("v4/contextual-json", frozen_v4_contextual_json(), @yaml.ContextualDraft1),
    ("v4/contextual-yaml", frozen_v4_contextual_yaml(), @yaml.ContextualDraft1),
  ]
}
