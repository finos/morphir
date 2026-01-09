---
id: typescript-api
sidebar_position: 12
---

# TypeScript API

The purpose of this document is describing the TypeScript API generated for Morphir
models by running `morphir-elm gen --target=TypeScript`.

## Generating TypeScript

Given a model represented in `morphir-ir.json`, you can generate a TypeScript
representation by running:

```bash
morphir-elm gen --input morphir-ir.json --output ./generated --target=TypeScript
```

Note that at present only the types are converted. Data values and functions
are not.

You can generate a TypeScript representation of the Morphir IR itself by
running this in the morphir-elm repo:

```bash
morphir-elm make ./morphir-make --types-only
morphir-elm gen --input=morphir-ir.json --output=./generated --target=TypeScript
```

## Using the generated types

The TypeScript backend outputs a top-level module per package, which your own
code should import. The namespaces correspond with the package and module names
in the IR. Only namespaces and symbols marked as public will be exported in the
TypeScript API.

For example, you can use the `IR` types from the `Morphir` package like this:

```typescript
import { Morphir } from './generated/Morphir'

const myName: Morphir.IR.Name.Name = ["this", "is", "a", "great", "name"]
```

Internally the types map to TypeScript type definitions. This is how a Morphir
IR `Name` would be represented in `generated/morphir/ir/Name.ts`:

```typescript
export type Name = Array<string>
```

You benefit from all the usual TypeScript type checking. For example, a Path
must be a list of Name instances, so this example will raise an error:

```typescript
import { Morphir } from './generated/Morphir'

const myName: Morphir.IR.Path.Path = "This is the wrong type."
```

You should see this message when compiling:

```
test.ts:3:7 - error TS2322: Type 'string' is not assignable to type 'Path'.
```

Most Morphir types correspond directly to JavaScript types. The
[JSON mapping](https://github.com/finos/morphir-elm/blob/main/docs/json-mapping.md)
gives a useful reference. There are some special cases, which are documented below.

### Type mapping details

#### Dict

A `Morphir.SDK.Dict.Dict K V` maps to a TypeScript `Map<K,V>`.

#### Custom types

We follow the example
["Tagged Union Types in TypeScript"](https://mariusschulz.com/blog/tagged-union-types-in-typescript)
to implement custom types.

Each type variant is a TypeScript `interface`, with a `kind` and maybe some
fields. The fields names are defined in the IR, and if you used `morphir-elm`
make to build the IR then the names will follow the pattern `arg1`, `arg2`,
`arg3` and so on.

Constructor functions are provided for these.  Here's an example using the
Morphir IR `Value` custom type, creating an instance of its `Reference`
variant:

```typescript
import { Morphir } from './generated/Morphir'

const exampleFQName: Morphir.IR.FQName.FQName = [[], [[]], ["excellent", "name"]];

type AttrType = [];
let myReference = new Morphir.IR.Value.Reference<AttrType>([], exampleFQName);
```

Calling the constructor function is equivalent to manually constructing an object
and setting the relevant properties:

```typescript
let myReference: Morphir.IR.Value.Reference<AttrType> = {
    kind: "Reference",
    arg1: [],
    arg2: exampleFQName,
}
```

Constructor functions are only provided for custom types.

#### Type variables

Morphir's custom types and type aliases can use type variables. These map to
TypeScript [generics](https://www.typescriptlang.org/docs/handbook/2/generics.html).

Here's an example using Morphir IR's `AccessControlled` type, which is a type
alias that maps to a Record.

```typescript
import { Morphir } from './generated/Morphir'

const myAccess = new Morphir.IR.AccessControlled.Public();

let myAccessControlled: Morphir.IR.AccessControlled.AccessControlled<String> = {
    access: myAccess,
    value: "I'm a string",
}
```

## JSON serialization and deserialization

The generated TypeScript API includes `decode` and `encode` functions for each
type, used to serialize and deserialize instances of the types according to the
[standard Morphir JSON mapping](https://github.com/finos/morphir-elm/blob/master/docs/json-mapping.md).

With the generated Morphir.IR API, this allows you to read entire `morphir-ir.json` files
into your TypeScript program and create instances of the appropriate types. Here's how you
might do that:

```typescript
import { Morphir } from './generated/Morphir'

function loadMorphirIR(text) {
    let data = JSON.parse(text);

    if (data['formatVersion'] != 2) {
        throw "Unsupported morphir-ir.json format";
    }

    return Morphir.IR.Distribution.decodeDistribution(data['distribution']);
}
```
