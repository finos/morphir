---
id: morphir-typescript
title: TypeScript - Morphir API
---

# Morphir API for Typescript 
The purpose of this documentation is to give a user an understanding of how to use the Morphir API created for Typescript.

This API basically enables adding morphir as a dependency in a Typescript project. This allows a user to have access to morphir 
types and modules to build tools and/or to aid work on the morphir generated IR. A use-case of the API is the Cadl frontend,
where the API provides modules in Morphir, mapping them to those in Cadl, in order to generate a Morphir IR as the Cadl emitter runs through
a Cadl project.

### How the Morphir API for Typescript is used.
To use the modules/Types from the morphir api, they'd need to be imported from `morphir-elm`, as shown below in an **example:**
```
import {toDistribution, Morphir} from "morphir-elm"

function getDistro():Morphir.IR.Distribution.Distribution {
    return toDistribution(distribution.toString('utf8'))
}
```


