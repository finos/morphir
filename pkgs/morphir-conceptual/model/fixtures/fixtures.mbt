///|
pub let prose_only : String =
  #|{
  #|  "recordVersion": "0.1.0-draft.1",
  #|  "profile": "morphir-conceptual/0.1.0-draft.1",
  #|  "model": { "id": "urn:example:lending", "revision": "model-1" },
  #|  "dependencies": [],
  #|  "requiredSemantics": [],
  #|  "sources": [
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:source:workshop",
  #|      "document": { "id": "urn:example:workshop-notes", "revision": "notes-1" },
  #|      "resolution": "retained", "locator": "notes/workshop.txt",
  #|      "fragments": [
  #|        { "anchor": "return", "text": "Track what borrowers still owe.\n\n  Retain the loan identity.\n" }
  #|      ]
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:source:external",
  #|      "document": { "id": "urn:example:external-policy" },
  #|      "resolution": "unresolved", "locator": "https://example.invalid/policy",
  #|      "reason": "Caller has not supplied a pinned source snapshot.", "fragments": []
  #|    }
  #|  ],
  #|  "entities": [
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:intent:returns", "revision": "i1",
  #|      "kind": "intent", "name": "Track returns",
  #|      "sourceRefs": [{ "sourceId": "urn:example:source:workshop", "anchor": "return" }],
  #|      "content": { "text": "Track what borrowers still owe.", "rationale": "Keep a loan's remaining obligation visible." }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:requirement:balance", "revision": "r1",
  #|      "kind": "requirement", "name": "Retain loan identity",
  #|      "sourceRefs": [{ "sourceId": "urn:example:source:workshop", "anchor": "return" }],
  #|      "content": { "category": "morphir:requirement-kind/functional", "text": "An accepted return retains the loan identity." },
  #|      "review": { "state": "pending", "entityRevision": "r1", "modelRevision": "model-1" }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:concept:borrower", "revision": "c1",
  #|      "kind": "concept", "name": "Borrower", "sourceRefs": [],
  #|      "content": { "definition": "The party that owes the loaned asset.", "aliases": ["Borrowing party"] },
  #|      "elaboration": { "state": "open", "aspects": [{ "id": "identity", "question": "Which identifying information is needed?", "rationale": "The domain meaning is known; its representation is undecided.", "sourceRefs": [] }] }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:fragment:return", "revision": "f1",
  #|      "kind": "sourceFragment", "name": "Workshop return paragraph",
  #|      "sourceRefs": [{ "sourceId": "urn:example:source:workshop", "anchor": "return" }],
  #|      "content": { "sourceId": "urn:example:source:workshop", "anchor": "return" }
  #|    }
  #|  ],
  #|  "relationships": [
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:link:refines",
  #|      "predicate": "morphir:refines",
  #|      "subject": { "state": "resolved", "modelId": "urn:example:lending", "modelRevision": "model-1", "entityId": "urn:example:requirement:balance", "entityRevision": "r1" },
  #|      "target": { "state": "resolved", "modelId": "urn:example:lending", "modelRevision": "model-1", "entityId": "urn:example:intent:returns", "entityRevision": "i1" },
  #|      "sourceRefs": []
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:link:source",
  #|      "predicate": "morphir:derivedFrom",
  #|      "subject": { "state": "resolved", "modelId": "urn:example:lending", "modelRevision": "model-1", "entityId": "urn:example:requirement:balance", "entityRevision": "r1" },
  #|      "target": { "state": "resolved", "modelId": "urn:example:lending", "modelRevision": "model-1", "entityId": "urn:example:fragment:return", "entityRevision": "f1" },
  #|      "sourceRefs": []
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:link:external",
  #|      "predicate": "morphir:derivedFrom",
  #|      "subject": { "state": "resolved", "modelId": "urn:example:lending", "modelRevision": "model-1", "entityId": "urn:example:requirement:balance", "entityRevision": "r1" },
  #|      "target": { "state": "unresolved", "locator": "https://example.invalid/policy#return", "expectedKind": "sourceFragment", "reason": "External document has not been supplied." },
  #|      "sourceRefs": []
  #|    }
  #|  ],
  #|  "capabilities": [],
  #|  "projectionGaps": []
  #|}

///|
pub let mixed : String =
  #|{
  #|  "recordVersion": "0.1.0-draft.1",
  #|  "profile": "morphir-conceptual/0.1.0-draft.1",
  #|  "model": {
  #|    "id": "urn:example:mixed",
  #|    "revision": "model-2"
  #|  },
  #|  "dependencies": [],
  #|  "requiredSemantics": [],
  #|  "sources": [
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:source:identity",
  #|      "document": {
  #|        "id": "urn:example:identity-source",
  #|        "revision": "source-2"
  #|      },
  #|      "resolution": "retained",
  #|      "locator": "identity.spec",
  #|      "fragments": [
  #|        {
  #|          "anchor": "identity",
  #|          "text": "fn identity(value: a) -> a\n"
  #|        }
  #|      ]
  #|    }
  #|  ],
  #|  "entities": [
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:concept:customer",
  #|      "revision": "c1",
  #|      "kind": "concept",
  #|      "name": "Customer",
  #|      "sourceRefs": [],
  #|      "content": {
  #|        "definition": "A party served by the organization.",
  #|        "aliases": []
  #|      },
  #|      "elaboration": {
  #|        "state": "open",
  #|        "aspects": [
  #|          {
  #|            "id": "representation",
  #|            "question": "Which customer identifier is appropriate?",
  #|            "rationale": "No type has been selected.",
  #|            "sourceRefs": []
  #|          }
  #|        ]
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:declaration:identity",
  #|      "revision": "d2",
  #|      "kind": "declaration",
  #|      "name": "identity",
  #|      "sourceRefs": [
  #|        {
  #|          "sourceId": "urn:example:source:identity",
  #|          "anchor": "identity"
  #|        }
  #|      ],
  #|      "content": {
  #|        "role": "function",
  #|        "fqName": "example/model:api#identity",
  #|        "typeParameters": [
  #|          "a"
  #|        ],
  #|        "signature": {
  #|          "inputs": {
  #|            "value": "a"
  #|          },
  #|          "output": "a"
  #|        }
  #|      },
  #|      "definition": {
  #|        "state": "completeSpecification"
  #|      },
  #|      "recovery": {
  #|        "state": "clean"
  #|      },
  #|      "implementation": {
  #|        "state": "bound",
  #|        "binding": {
  #|          "state": "resolved",
  #|          "modelId": "urn:example:mixed",
  #|          "modelRevision": "model-2",
  #|          "entityId": "urn:example:implementation:identity",
  #|          "entityRevision": "impl-2"
  #|        }
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:implementation:identity",
  #|      "revision": "impl-2",
  #|      "kind": "implementation",
  #|      "name": "Identity implementation",
  #|      "sourceRefs": [],
  #|      "content": {
  #|        "artifact": {
  #|          "id": "urn:example:identity-library",
  #|          "revision": "library-2"
  #|        },
  #|        "fqName": "example/model:api#identity",
  #|        "availability": "supplied"
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:requirement:identity",
  #|      "revision": "r2",
  #|      "kind": "requirement",
  #|      "name": "Return the argument",
  #|      "sourceRefs": [],
  #|      "content": {
  #|        "category": "morphir:requirement-kind/functional",
  #|        "text": "Return the supplied value unchanged."
  #|      },
  #|      "review": {
  #|        "state": "accepted",
  #|        "entityRevision": "r2",
  #|        "modelRevision": "model-2",
  #|        "reviewer": "urn:example:reviewer:alice",
  #|        "rationale": "Reviewed only this interpretation."
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:contract:identity",
  #|      "revision": "k2",
  #|      "kind": "contract",
  #|      "name": "Identity result",
  #|      "sourceRefs": [],
  #|      "content": {
  #|        "notation": {
  #|          "profile": "urn:example:predicate-source/0.1.0-draft.1",
  #|          "text": "result == value"
  #|        },
  #|        "binders": [
  #|          {
  #|            "id": "value",
  #|            "role": "argument",
  #|            "position": 0,
  #|            "name": "value",
  #|            "type": "a"
  #|          },
  #|          {
  #|            "id": "result",
  #|            "role": "result",
  #|            "name": "result",
  #|            "type": "a"
  #|          }
  #|        ],
  #|        "expression": {
  #|          "state": "resolved",
  #|          "profile": "urn:example:equality/0.1.0-draft.1",
  #|          "ast": {
  #|            "equal": [
  #|              {
  #|                "binder": "result"
  #|              },
  #|              {
  #|                "binder": "value"
  #|              }
  #|            ]
  #|          }
  #|        },
  #|        "clauseKind": "postcondition",
  #|        "subject": {
  #|          "state": "resolved",
  #|          "modelId": "urn:example:mixed",
  #|          "modelRevision": "model-2",
  #|          "entityId": "urn:example:declaration:identity",
  #|          "entityRevision": "d2"
  #|        }
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:scenario:identity",
  #|      "revision": "s2",
  #|      "kind": "scenario",
  #|      "name": "Identity of seven",
  #|      "sourceRefs": [],
  #|      "content": {
  #|        "valueProfile": "urn:example:exact-int/0.1.0-draft.1",
  #|        "inputs": {
  #|          "value": "7"
  #|        },
  #|        "expected": "7",
  #|        "origin": {
  #|          "kind": "authored",
  #|          "author": "urn:example:fixture-author"
  #|        },
  #|        "typeArguments": {
  #|          "a": "morphir/SDK:basics#int"
  #|        }
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:claim:identity",
  #|      "revision": "claim-2",
  #|      "kind": "claim",
  #|      "name": "Identity for the supplied example",
  #|      "sourceRefs": [],
  #|      "content": {
  #|        "subject": {
  #|          "state": "resolved",
  #|          "modelId": "urn:example:mixed",
  #|          "modelRevision": "model-2",
  #|          "entityId": "urn:example:declaration:identity",
  #|          "entityRevision": "d2"
  #|        },
  #|        "proposition": "The implementation returns seven for argument seven.",
  #|        "author": "urn:example:fixture-author",
  #|        "scope": {
  #|          "scenarioIds": [
  #|            "urn:example:scenario:identity"
  #|          ]
  #|        },
  #|        "context": {
  #|          "model": {
  #|            "id": "urn:example:mixed",
  #|            "revision": "model-2"
  #|          },
  #|          "entities": [
  #|            {
  #|              "id": "urn:example:requirement:identity",
  #|              "revision": "r2"
  #|            },
  #|            {
  #|              "id": "urn:example:contract:identity",
  #|              "revision": "k2"
  #|            },
  #|            {
  #|              "id": "urn:example:declaration:identity",
  #|              "revision": "d2"
  #|            },
  #|            {
  #|              "id": "urn:example:scenario:identity",
  #|              "revision": "s2"
  #|            },
  #|            {
  #|              "id": "urn:example:implementation:identity",
  #|              "revision": "impl-2"
  #|            }
  #|          ],
  #|          "sources": [
  #|            {
  #|              "id": "urn:example:identity-source",
  #|              "revision": "source-2"
  #|            }
  #|          ],
  #|          "implementations": [
  #|            {
  #|              "id": "urn:example:identity-library",
  #|              "revision": "library-2"
  #|            }
  #|          ]
  #|        }
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:evidence:identity",
  #|      "revision": "e2",
  #|      "kind": "evidence",
  #|      "name": "Illustrative observation",
  #|      "sourceRefs": [],
  #|      "content": {
  #|        "evidenceKind": "run",
  #|        "origin": "hand-authored-fixture",
  #|        "context": {
  #|          "model": {
  #|            "id": "urn:example:mixed",
  #|            "revision": "model-2"
  #|          },
  #|          "entities": [
  #|            {
  #|              "id": "urn:example:requirement:identity",
  #|              "revision": "r2"
  #|            },
  #|            {
  #|              "id": "urn:example:contract:identity",
  #|              "revision": "k2"
  #|            },
  #|            {
  #|              "id": "urn:example:declaration:identity",
  #|              "revision": "d2"
  #|            },
  #|            {
  #|              "id": "urn:example:scenario:identity",
  #|              "revision": "s2"
  #|            },
  #|            {
  #|              "id": "urn:example:implementation:identity",
  #|              "revision": "impl-2"
  #|            }
  #|          ],
  #|          "sources": [
  #|            {
  #|              "id": "urn:example:identity-source",
  #|              "revision": "source-2"
  #|            }
  #|          ],
  #|          "implementations": [
  #|            {
  #|              "id": "urn:example:identity-library",
  #|              "revision": "library-2"
  #|            }
  #|          ]
  #|        },
  #|        "valueProfile": "urn:example:exact-int/0.1.0-draft.1",
  #|        "input": {
  #|          "value": "7"
  #|        },
  #|        "clauses": [
  #|          {
  #|            "entityId": "urn:example:contract:identity",
  #|            "entityRevision": "k2",
  #|            "observation": "satisfied"
  #|          }
  #|        ],
  #|        "evaluator": {
  #|          "id": "urn:example:fixture-evaluator",
  #|          "version": "0.1.0-draft.1",
  #|          "profile": "urn:example:equality/0.1.0-draft.1"
  #|        },
  #|        "environment": {
  #|          "target": "fixture-only",
  #|          "configuration": {}
  #|        },
  #|        "limits": {
  #|          "steps": 100,
  #|          "depth": 16
  #|        },
  #|        "note": "A literal for future runner tests; no execution occurred in M1.",
  #|        "typeArguments": {
  #|          "a": "morphir/SDK:basics#int"
  #|        },
  #|        "output": {
  #|          "state": "observed",
  #|          "value": "7"
  #|        }
  #|      }
  #|    }
  #|  ],
  #|  "relationships": [
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:link:formalizes",
  #|      "predicate": "morphir:formalizes",
  #|      "subject": {
  #|        "state": "resolved",
  #|        "modelId": "urn:example:mixed",
  #|        "modelRevision": "model-2",
  #|        "entityId": "urn:example:contract:identity",
  #|        "entityRevision": "k2"
  #|      },
  #|      "target": {
  #|        "state": "resolved",
  #|        "modelId": "urn:example:mixed",
  #|        "modelRevision": "model-2",
  #|        "entityId": "urn:example:requirement:identity",
  #|        "entityRevision": "r2"
  #|      },
  #|      "sourceRefs": []
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:link:governed",
  #|      "predicate": "morphir:governedBy",
  #|      "subject": {
  #|        "state": "resolved",
  #|        "modelId": "urn:example:mixed",
  #|        "modelRevision": "model-2",
  #|        "entityId": "urn:example:declaration:identity",
  #|        "entityRevision": "d2"
  #|      },
  #|      "target": {
  #|        "state": "resolved",
  #|        "modelId": "urn:example:mixed",
  #|        "modelRevision": "model-2",
  #|        "entityId": "urn:example:contract:identity",
  #|        "entityRevision": "k2"
  #|      },
  #|      "sourceRefs": []
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:link:implements",
  #|      "predicate": "morphir:implements",
  #|      "subject": {
  #|        "state": "resolved",
  #|        "modelId": "urn:example:mixed",
  #|        "modelRevision": "model-2",
  #|        "entityId": "urn:example:implementation:identity",
  #|        "entityRevision": "impl-2"
  #|      },
  #|      "target": {
  #|        "state": "resolved",
  #|        "modelId": "urn:example:mixed",
  #|        "modelRevision": "model-2",
  #|        "entityId": "urn:example:declaration:identity",
  #|        "entityRevision": "d2"
  #|      },
  #|      "sourceRefs": []
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:link:exercises",
  #|      "predicate": "morphir:exercises",
  #|      "subject": {
  #|        "state": "resolved",
  #|        "modelId": "urn:example:mixed",
  #|        "modelRevision": "model-2",
  #|        "entityId": "urn:example:scenario:identity",
  #|        "entityRevision": "s2"
  #|      },
  #|      "target": {
  #|        "state": "resolved",
  #|        "modelId": "urn:example:mixed",
  #|        "modelRevision": "model-2",
  #|        "entityId": "urn:example:contract:identity",
  #|        "entityRevision": "k2"
  #|      },
  #|      "sourceRefs": []
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:link:supports",
  #|      "predicate": "morphir:supports",
  #|      "subject": {
  #|        "state": "resolved",
  #|        "modelId": "urn:example:mixed",
  #|        "modelRevision": "model-2",
  #|        "entityId": "urn:example:evidence:identity",
  #|        "entityRevision": "e2"
  #|      },
  #|      "target": {
  #|        "state": "resolved",
  #|        "modelId": "urn:example:mixed",
  #|        "modelRevision": "model-2",
  #|        "entityId": "urn:example:claim:identity",
  #|        "entityRevision": "claim-2"
  #|      },
  #|      "sourceRefs": []
  #|    }
  #|  ],
  #|  "capabilities": [
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:capability:preserver",
  #|      "provider": {
  #|        "id": "urn:example:preserver",
  #|        "revision": "provider-1"
  #|      },
  #|      "profile": "morphir-conceptual/0.1.0-draft.1",
  #|      "operations": [
  #|        "preserve",
  #|        "inspect",
  #|        "check"
  #|      ],
  #|      "semanticProfiles": [],
  #|      "limits": {
  #|        "bytes": 4194304,
  #|        "depth": 128,
  #|        "values": 100000
  #|      }
  #|    }
  #|  ],
  #|  "projectionGaps": []
  #|}

///|
pub let independent_concerns : String =
  #|{
  #|  "recordVersion": "0.1.0-draft.1", "profile": "morphir-conceptual/0.1.0-draft.1",
  #|  "model": { "id": "urn:example:concerns", "revision": "m1" },
  #|  "dependencies": [], "requiredSemantics": [],
  #|  "sources": [{
  #|    "recordVersion": "0.1.0-draft.1", "id": "urn:example:source:editor",
  #|    "document": { "id": "urn:example:editor", "revision": "edit-1" },
  #|    "resolution": "retained", "locator": "editor.spec",
  #|    "fragments": [{ "anchor": "draft", "text": "fn draft(x: Int) -> Int { renamed( }\n" }]
  #|  }],
  #|  "entities": [
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:concept:party", "revision": "c1", "kind": "concept", "name": "Party", "sourceRefs": [],
  #|      "content": { "definition": "A participant in a loan.", "aliases": [] },
  #|      "elaboration": { "state": "open", "aspects": [{ "id": "representation", "question": "Which identifiers?", "rationale": "Domain work remains.", "sourceRefs": [] }] }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:declaration:draft", "revision": "d1", "kind": "declaration", "name": "draft", "sourceRefs": [{ "sourceId": "urn:example:source:editor", "anchor": "draft" }],
  #|      "content": { "role": "function", "typeParameters": [], "signature": { "inputs": { "x": "morphir/SDK:basics#int" }, "output": "morphir/SDK:basics#int" } },
  #|      "elaboration": { "state": "open", "aspects": [{ "id": "zero-policy", "question": "What does zero mean?", "rationale": "Independent of the broken editor reference.", "sourceRefs": [] }] },
  #|      "definition": { "state": "authoredPartial", "reason": "The author has started the body.", "sourceRefs": [{ "sourceId": "urn:example:source:editor", "anchor": "draft" }] },
  #|      "recovery": { "state": "recovering", "sourceRef": { "sourceId": "urn:example:source:editor", "anchor": "draft" }, "diagnostics": [{ "code": "fixture.syntax.expected-expression", "message": "An expression is missing after the opening parenthesis.", "span": { "start": 34, "end": 35, "unit": "utf8-byte" } }] },
  #|      "review": { "state": "pending", "entityRevision": "d1", "modelRevision": "m1" },
  #|      "implementation": { "state": "unbound" }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:declaration:identity", "revision": "d1", "kind": "declaration", "name": "identity", "sourceRefs": [],
  #|      "content": { "role": "function", "fqName": "example/concerns:api#identity", "typeParameters": ["a"], "signature": { "inputs": { "value": "a" }, "output": "a" } },
  #|      "definition": { "state": "completeSpecification" }, "recovery": { "state": "clean" }, "implementation": { "state": "unbound" }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:declaration:loan-id", "revision": "t1", "kind": "declaration", "name": "LoanId", "sourceRefs": [],
  #|      "content": { "role": "type", "fqName": "example/concerns:api#loan-id", "typeParameters": [], "visibility": "opaque", "representation": { "state": "known", "type": "morphir/SDK:string#string", "access": "defining-module" }, "publicSpecification": { "OpaqueTypeSpecification": {} } },
  #|      "definition": { "state": "completeSpecification" }, "recovery": { "state": "clean" }
  #|    }
  #|  ],
  #|  "relationships": [], "capabilities": [],
  #|  "projectionGaps": [{ "entityId": "urn:example:declaration:draft", "reason": "Compiler recovery has no resolved declaration to project.", "requiredCapability": "morphir:recovery-projection" }]
  #|}

///|
pub let contract_kinds : String =
  #|{
  #|  "recordVersion": "0.1.0-draft.1", "profile": "morphir-conceptual/0.1.0-draft.1",
  #|  "model": { "id": "urn:example:clauses", "revision": "m1" },
  #|  "dependencies": [], "requiredSemantics": [], "sources": [],
  #|  "entities": [
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:type:quantity", "revision": "t1", "kind": "declaration", "name": "Quantity", "sourceRefs": [],
  #|      "content": { "role": "type", "typeParameters": [], "visibility": "transparent", "representation": { "state": "known", "type": "morphir/SDK:basics#int", "access": "public" } },
  #|      "definition": { "state": "completeSpecification" }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:type:interval", "revision": "t1", "kind": "declaration", "name": "Interval", "sourceRefs": [],
  #|      "content": { "role": "type", "typeParameters": [], "visibility": "transparent", "representation": { "state": "known", "type": { "Record": { "fields": { "lower": "morphir/SDK:basics#int", "upper": "morphir/SDK:basics#int" } } }, "access": "public" } },
  #|      "definition": { "state": "completeSpecification" }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:function:remaining", "revision": "f1", "kind": "declaration", "name": "remaining", "sourceRefs": [],
  #|      "content": { "role": "function", "typeParameters": [], "signature": { "inputs": { "outstanding": "morphir/SDK:basics#int", "returned": "morphir/SDK:basics#int" }, "output": "morphir/SDK:basics#int" } },
  #|      "definition": { "state": "completeSpecification" }, "implementation": { "state": "unbound" }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:clause:quantity", "revision": "c1", "kind": "contract", "name": "Nonnegative quantity", "sourceRefs": [],
  #|      "content": {
  #|        "clauseKind": "refinement", "subject": { "state": "resolved", "modelId": "urn:example:clauses", "modelRevision": "m1", "entityId": "urn:example:type:quantity", "entityRevision": "t1" },
  #|        "notation": { "profile": "urn:example:scalar-source/0.1.0-draft.1", "text": "self >= 0" },
  #|        "binders": [{ "id": "self", "role": "self", "name": "self", "type": "morphir/SDK:basics#int" }],
  #|        "expression": { "state": "resolved", "profile": "urn:example:scalar/0.1.0-draft.1", "ast": { "gte": [{ "binder": "self" }, { "int": "0" }] } }
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:clause:interval", "revision": "c1", "kind": "contract", "name": "Ordered interval", "sourceRefs": [],
  #|      "content": {
  #|        "clauseKind": "invariant", "subject": { "state": "resolved", "modelId": "urn:example:clauses", "modelRevision": "m1", "entityId": "urn:example:type:interval", "entityRevision": "t1" },
  #|        "notation": { "profile": "urn:example:scalar-source/0.1.0-draft.1", "text": "self.lower <= self.upper" },
  #|        "binders": [{ "id": "self", "role": "self", "name": "self", "type": { "Record": { "fields": { "lower": "morphir/SDK:basics#int", "upper": "morphir/SDK:basics#int" } } } }],
  #|        "expression": { "state": "resolved", "profile": "urn:example:scalar/0.1.0-draft.1", "ast": { "lte": [{ "field": [{ "binder": "self" }, "lower"] }, { "field": [{ "binder": "self" }, "upper"] }] } }
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:clause:remaining-pre", "revision": "c1", "kind": "contract", "name": "Return does not exceed balance", "sourceRefs": [],
  #|      "content": {
  #|        "clauseKind": "precondition", "subject": { "state": "resolved", "modelId": "urn:example:clauses", "modelRevision": "m1", "entityId": "urn:example:function:remaining", "entityRevision": "f1" },
  #|        "notation": { "profile": "urn:example:scalar-source/0.1.0-draft.1", "text": "returned <= outstanding" },
  #|        "binders": [{ "id": "outstanding", "role": "argument", "position": 0, "name": "outstanding", "type": "morphir/SDK:basics#int" }, { "id": "returned", "role": "argument", "position": 1, "name": "returned", "type": "morphir/SDK:basics#int" }],
  #|        "expression": { "state": "resolved", "profile": "urn:example:scalar/0.1.0-draft.1", "ast": { "lte": [{ "binder": "returned" }, { "binder": "outstanding" }] } }
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1", "id": "urn:example:clause:remaining-post", "revision": "c1", "kind": "contract", "name": "Subtract returned amount", "sourceRefs": [],
  #|      "content": {
  #|        "clauseKind": "postcondition", "subject": { "state": "resolved", "modelId": "urn:example:clauses", "modelRevision": "m1", "entityId": "urn:example:function:remaining", "entityRevision": "f1" },
  #|        "notation": { "profile": "urn:example:scalar-source/0.1.0-draft.1", "text": "result == outstanding - returned" },
  #|        "binders": [{ "id": "outstanding", "role": "argument", "position": 0, "name": "outstanding", "type": "morphir/SDK:basics#int" }, { "id": "returned", "role": "argument", "position": 1, "name": "returned", "type": "morphir/SDK:basics#int" }, { "id": "result", "role": "result", "name": "result", "type": "morphir/SDK:basics#int" }],
  #|        "expression": { "state": "resolved", "profile": "urn:example:scalar/0.1.0-draft.1", "ast": { "equal": [{ "binder": "result" }, { "subtract": [{ "binder": "outstanding" }, { "binder": "returned" }] }] } }
  #|      }
  #|    }
  #|  ],
  #|  "relationships": [],
  #|  "capabilities": [{ "recordVersion": "0.1.0-draft.1", "id": "urn:example:capability:scalar", "provider": { "id": "urn:example:future-scalar-adapter", "revision": "p1" }, "profile": "morphir-conceptual/0.1.0-draft.1", "operations": ["inspect", "check"], "semanticProfiles": ["urn:example:scalar/0.1.0-draft.1"], "limits": { "bytes": 4194304, "depth": 128, "values": 100000 } }],
  #|  "projectionGaps": []
  #|}

///|
pub let traits : String =
  #|{
  #|  "recordVersion": "0.1.0-draft.1",
  #|  "profile": "morphir-conceptual/0.1.0-draft.1",
  #|  "model": {
  #|    "id": "urn:example:trait-model",
  #|    "revision": "model-1"
  #|  },
  #|  "dependencies": [],
  #|  "requiredSemantics": [],
  #|  "sources": [
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:trait-source",
  #|      "document": {
  #|        "id": "urn:example:source-document",
  #|        "revision": "source-1"
  #|      },
  #|      "resolution": "retained",
  #|      "locator": "fixture:trait-authoring",
  #|      "fragments": [
  #|        {
  #|          "anchor": "urn:example:trait-source#wording",
  #|          "text": "Quantity keeps its meaning before encoding is chosen.\n\n  Keep this wording.\n"
  #|        }
  #|      ]
  #|    }
  #|  ],
  #|  "entities": [
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:concept:quantity",
  #|      "revision": "e1",
  #|      "kind": "concept",
  #|      "name": "concept:quantity",
  #|      "sourceRefs": [
  #|        {
  #|          "sourceId": "urn:example:trait-source",
  #|          "anchor": "urn:example:trait-source#wording"
  #|        }
  #|      ],
  #|      "content": {
  #|        "definition": "An amount counted in units.",
  #|        "aliases": [
  #|          "Quantity"
  #|        ]
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:type:quantity",
  #|      "revision": "e1",
  #|      "kind": "declaration",
  #|      "name": "type:quantity",
  #|      "sourceRefs": [
  #|        {
  #|          "sourceId": "urn:example:trait-source",
  #|          "anchor": "urn:example:trait-source#wording"
  #|        }
  #|      ],
  #|      "content": {
  #|        "role": "type",
  #|        "typeParameters": [],
  #|        "visibility": "transparent",
  #|        "representation": {
  #|          "state": "known",
  #|          "type": "morphir/SDK:basics#int",
  #|          "access": "public"
  #|        }
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:member:quantity",
  #|      "revision": "e1",
  #|      "kind": "declaration",
  #|      "name": "member:quantity",
  #|      "sourceRefs": [
  #|        {
  #|          "sourceId": "urn:example:trait-source",
  #|          "anchor": "urn:example:trait-source#wording"
  #|        }
  #|      ],
  #|      "content": {
  #|        "role": "parameter",
  #|        "parent": {
  #|          "state": "resolved",
  #|          "modelId": "urn:example:trait-model",
  #|          "modelRevision": "model-1",
  #|          "entityId": "urn:example:function:accept",
  #|          "entityRevision": "e1"
  #|        },
  #|        "type": "morphir/SDK:basics#int"
  #|      }
  #|    },
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:function:accept",
  #|      "revision": "e1",
  #|      "kind": "declaration",
  #|      "name": "function:accept",
  #|      "sourceRefs": [
  #|        {
  #|          "sourceId": "urn:example:trait-source",
  #|          "anchor": "urn:example:trait-source#wording"
  #|        }
  #|      ],
  #|      "content": {
  #|        "role": "function",
  #|        "typeParameters": [],
  #|        "signature": {
  #|          "inputs": {
  #|            "quantity": "morphir/SDK:basics#int"
  #|          },
  #|          "output": "morphir/SDK:basics#int"
  #|        }
  #|      }
  #|    }
  #|  ],
  #|  "relationships": [],
  #|  "capabilities": [],
  #|  "projectionGaps": [],
  #|  "traits": {
  #|    "recordVersion": "0.1.0-draft.1",
  #|    "profile": "morphir-traits/0.1.0-draft.1",
  #|    "definitions": [
  #|      {
  #|        "recordVersion": "0.1.0-draft.1",
  #|        "id": "urn:example:trait:label",
  #|        "revision": "d1",
  #|        "name": "label",
  #|        "targets": [
  #|          "model",
  #|          "module",
  #|          "concept",
  #|          "type",
  #|          "member",
  #|          "function",
  #|          "operation",
  #|          "serviceBinding"
  #|        ],
  #|        "payloadSchema": {
  #|          "artifact": {
  #|            "id": "urn:example:trait-payloads",
  #|            "revision": "types-1"
  #|          },
  #|          "fqName": "example/traits:payload#label",
  #|          "typeArguments": [],
  #|          "dataProfile": "morphir-metadata-json/0.1.0-draft.1"
  #|        },
  #|        "interpretation": {
  #|          "kind": "descriptive"
  #|        },
  #|        "multiplicity": "many",
  #|        "sourceRefs": [
  #|          {
  #|            "sourceId": "urn:example:trait-source",
  #|            "anchor": "urn:example:trait-source#wording"
  #|          }
  #|        ]
  #|      },
  #|      {
  #|        "recordVersion": "0.1.0-draft.1",
  #|        "id": "urn:example:trait:elaboration",
  #|        "revision": "d1",
  #|        "name": "elaboration",
  #|        "targets": [
  #|          "concept",
  #|          "type",
  #|          "member"
  #|        ],
  #|        "payloadSchema": {
  #|          "artifact": {
  #|            "id": "urn:example:trait-payloads",
  #|            "revision": "types-1"
  #|          },
  #|          "fqName": "example/traits:payload#elaboration",
  #|          "typeArguments": [],
  #|          "dataProfile": "morphir-metadata-json/0.1.0-draft.1"
  #|        },
  #|        "interpretation": {
  #|          "kind": "descriptive"
  #|        },
  #|        "multiplicity": "many",
  #|        "sourceRefs": [
  #|          {
  #|            "sourceId": "urn:example:trait-source",
  #|            "anchor": "urn:example:trait-source#wording"
  #|          }
  #|        ]
  #|      },
  #|      {
  #|        "recordVersion": "0.1.0-draft.1",
  #|        "id": "urn:example:trait:encoding",
  #|        "revision": "d1",
  #|        "name": "encoding",
  #|        "targets": [
  #|          "type"
  #|        ],
  #|        "payloadSchema": {
  #|          "artifact": {
  #|            "id": "urn:example:trait-payloads",
  #|            "revision": "types-1"
  #|          },
  #|          "fqName": "example/traits:payload#encoding",
  #|          "typeArguments": [],
  #|          "dataProfile": "morphir-metadata-json/0.1.0-draft.1"
  #|        },
  #|        "interpretation": {
  #|          "kind": "semantic",
  #|          "profiles": [
  #|            "urn:example:encoding-rules/0.1.0-draft.1"
  #|          ]
  #|        },
  #|        "multiplicity": "one",
  #|        "sourceRefs": [
  #|          {
  #|            "sourceId": "urn:example:trait-source",
  #|            "anchor": "urn:example:trait-source#wording"
  #|          }
  #|        ]
  #|      },
  #|      {
  #|        "recordVersion": "0.1.0-draft.1",
  #|        "id": "urn:example:trait:related-concept",
  #|        "revision": "d1",
  #|        "name": "related-concept",
  #|        "targets": [
  #|          "type",
  #|          "member"
  #|        ],
  #|        "payloadSchema": {
  #|          "artifact": {
  #|            "id": "urn:example:trait-payloads",
  #|            "revision": "types-1"
  #|          },
  #|          "fqName": "example/traits:payload#concept-link",
  #|          "typeArguments": [],
  #|          "dataProfile": "morphir-metadata-json/0.1.0-draft.1"
  #|        },
  #|        "interpretation": {
  #|          "kind": "descriptive"
  #|        },
  #|        "multiplicity": "many",
  #|        "sourceRefs": [
  #|          {
  #|            "sourceId": "urn:example:trait-source",
  #|            "anchor": "urn:example:trait-source#wording"
  #|          }
  #|        ],
  #|        "referenceBindings": [
  #|          {
  #|            "path": "",
  #|            "targetKind": "concept",
  #|            "profile": "morphir-entity-reference-data/0.1.0-draft.1"
  #|          }
  #|        ]
  #|      },
  #|      {
  #|        "recordVersion": "0.1.0-draft.1",
  #|        "id": "urn:example:trait:foreign-condition",
  #|        "revision": "d1",
  #|        "name": "foreign-condition",
  #|        "targets": [
  #|          "type",
  #|          "member"
  #|        ],
  #|        "payloadSchema": {
  #|          "artifact": {
  #|            "id": "urn:example:trait-payloads",
  #|            "revision": "types-1"
  #|          },
  #|          "fqName": "example/traits:payload#foreign-condition",
  #|          "typeArguments": [],
  #|          "dataProfile": "morphir-metadata-json/0.1.0-draft.1"
  #|        },
  #|        "interpretation": {
  #|          "kind": "semantic",
  #|          "profiles": [
  #|            "urn:example:foreign-condition/0.1.0-draft.1"
  #|          ]
  #|        },
  #|        "multiplicity": "many",
  #|        "sourceRefs": [
  #|          {
  #|            "sourceId": "urn:example:trait-source",
  #|            "anchor": "urn:example:trait-source#wording"
  #|          }
  #|        ]
  #|      },
  #|      {
  #|        "recordVersion": "0.1.0-draft.1",
  #|        "id": "urn:example:trait:prompt",
  #|        "revision": "d1",
  #|        "name": "prompt",
  #|        "targets": [
  #|          "operation",
  #|          "serviceBinding"
  #|        ],
  #|        "payloadSchema": {
  #|          "artifact": {
  #|            "id": "urn:example:trait-payloads",
  #|            "revision": "types-1"
  #|          },
  #|          "fqName": "example/traits:payload#prompt",
  #|          "typeArguments": [],
  #|          "dataProfile": "morphir-metadata-json/0.1.0-draft.1"
  #|        },
  #|        "interpretation": {
  #|          "kind": "descriptive"
  #|        },
  #|        "multiplicity": "many",
  #|        "sourceRefs": [
  #|          {
  #|            "sourceId": "urn:example:trait-source",
  #|            "anchor": "urn:example:trait-source#wording"
  #|          }
  #|        ]
  #|      }
  #|    ],
  #|    "applications": [
  #|      {
  #|        "recordVersion": "0.1.0-draft.1",
  #|        "id": "urn:example:application:label",
  #|        "revision": "a1",
  #|        "definition": {
  #|          "state": "resolved",
  #|          "modelId": "urn:example:trait-model",
  #|          "modelRevision": "model-1",
  #|          "entityId": "urn:example:trait:label",
  #|          "entityRevision": "d1"
  #|        },
  #|        "target": {
  #|          "kind": "type",
  #|          "ref": {
  #|            "state": "resolved",
  #|            "modelId": "urn:example:trait-model",
  #|            "modelRevision": "model-1",
  #|            "entityId": "urn:example:type:quantity",
  #|            "entityRevision": "e1"
  #|          }
  #|        },
  #|        "interpretation": {
  #|          "kind": "descriptive"
  #|        },
  #|        "payload": "Quantity",
  #|        "sourceRefs": [
  #|          {
  #|            "sourceId": "urn:example:trait-source",
  #|            "anchor": "urn:example:trait-source#wording"
  #|          }
  #|        ],
  #|        "provenance": {
  #|          "origin": "authored",
  #|          "agent": "fixture-author",
  #|          "sourceRefs": [
  #|            {
  #|              "sourceId": "urn:example:trait-source",
  #|              "anchor": "urn:example:trait-source#wording"
  #|            }
  #|          ]
  #|        }
  #|      }
  #|    ]
  #|  }
  #|}

///|
pub let dictionary : String =
  #|{
  #|  "recordVersion": "0.1.0-draft.1",
  #|  "profile": "morphir-conceptual/0.1.0-draft.1",
  #|  "model": {
  #|    "id": "urn:example:dictionary",
  #|    "revision": "dict-1"
  #|  },
  #|  "dependencies": [],
  #|  "requiredSemantics": [],
  #|  "sources": [],
  #|  "entities": [
  #|    {
  #|      "recordVersion": "0.1.0-draft.1",
  #|      "id": "urn:example:dictionary:quantity",
  #|      "revision": "concept-1",
  #|      "kind": "concept",
  #|      "name": "Quantity",
  #|      "sourceRefs": [],
  #|      "content": {
  #|        "definition": "An amount counted in units.",
  #|        "aliases": []
  #|      }
  #|    }
  #|  ],
  #|  "relationships": [],
  #|  "capabilities": [],
  #|  "projectionGaps": []
  #|}

///|
pub let model_unknown : String =
  #|future_note::source_wording::{
  #|  preciseCount: 9007199254740993,
  #|  amount: 123.4500,
  #|  vocabulary: pending,
  #|  typedNull: null.string,
  #|  wording: "Borrower\n\n  Keep spaces.\n",
  #|  facts: future_vocabulary::{enabled: true}
  #|}

///|
pub let traits_unknown : String =
  #|future_trait::{preciseCount: 9007199254740993, amount: 123.4500, vocabulary: pending, typedNull: null.string}

///|
pub let prose_only_ir : String =
  #|{
  #|  "formatVersion": 4,
  #|  "distribution": {
  #|    "Specs": { "packageName": "example/prose", "dependencies": {}, "spec": { "modules": {} } }
  #|  }
  #|}

///|
pub let mixed_ir : String =
  #|{
  #|  "formatVersion": 4,
  #|  "distribution": {
  #|    "Specs": {
  #|      "packageName": "example/model", "dependencies": {},
  #|      "spec": { "modules": { "api": { "types": {}, "values": { "identity": { "inputs": { "value": "a" }, "output": "a" } } } } }
  #|    }
  #|  }
  #|}

///|
pub let identity_implementation_ir : String =
  #|{
  #|  "formatVersion": 4,
  #|  "distribution": {
  #|    "Library": {
  #|      "packageName": "example/model", "dependencies": {},
  #|      "def": { "modules": { "api": { "access": "Public", "value": {
  #|        "types": {},
  #|        "values": { "identity": { "access": "Public", "value": { "ExpressionBody": {
  #|          "inputTypes": { "value": "a" }, "outputType": "a", "body": { "Variable": "value" }
  #|        } } } }
  #|      } } } }
  #|    }
  #|  }
  #|}
