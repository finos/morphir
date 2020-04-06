# Model Versioning

## Properties

Model versioning in Morphir is very similar to library versioning in any 
other programming language but thanks to the declarative nature of the 
language it is much more automated and convenient for the modeler. It 
was largely inspired by Elm that has enforced semantic versioning but 
has been adapted and extended to fit our requirements better. Below is 
a high-level overview of the important properties that should give you 
a general idea on what you can expect.

### Automatic

Morphir comes with automatic enforced versioning out-of-the-box. Users of
Morphir never have to (and are not allowed to) specify model versions 
manually. Instead the Morphir tooling will compare the current version of
the model to the latest previously released version and increase the 
version number if needed.

### Granular

Versioning is applied at a much more granular level compared to 
traditional package management systems. The lowest level of granularity
is a named function (or value) or type within a module. This allows 
users to track changes in the logic very accurately.

### Hierarchical

Versioning is also applied on higher levels of the package hierarchy.
This allows users to pick the right level of granularity for their 
use-case and even flip between different levels as needed.

Here are the different granularity levels where versioning is available:

1. Function implementations within a module.
2. Function types, types and type aliases within a module.
3. Modules.
4. Package.

### Sequential and Semantic

Morphir generates semantic (major.minor.path) versions on a package level 
to make it more informative to users but on lower levels of the 
hierarchy it uses simple sequential version numbers. 

## Implementation

### Overview

Versioning is implemented as a self-contained add-on working separately 
from all other Morphir tooling. This means that you can run a command to 
calculate versions at any point in time. Versioning takes source model, 
target model and source versions as inputs and returns target versions 
as the output. This can be formalized as:

```
Model -> Model -> Versions -> Versions
```    

This can be further broken down into two functions: first we calculate 
the diff between two models, then we use the diff to calculate new 
version numbers using the last released versions.

### Diffing

Since the model is represented as an AST we can do simple tree diffing.
The resulting diff is a set of insert, update and delete operations on
each leaf node (types and functions within a module). Versions on higher 
levels of the hierarchy are then derived from lower levels increasing
the version number if there were any changes below the node. 

Finally, on the package level we calculate the semantic version using 
the following rules:

* **Patch**: If there are no changes above level 1. In other words if 
only the implementation changed without any API changes. 
* **Minor**: If there are new functions/types added but none of the 
existing
APIs changed or got removed.
* **Major**: If any existing APIs changed.


### Versions File

Versions are stored in a JSON file for convenient access from any 
technology. By default version files are stored on AFS under the 
```etc/morphir``` directory in ```versions.json``` file. 

The format is easy to follow based on the properties described above. 
Here is the general layout:

* ```package```: This is the name of the package.
* ```semantic```: This is the semantic version number for the package.
* ```sequence```: This is the sequential version number for the package.
* ```modules```: This is a JSON object where each field corresponds to a 
module. Fully-qualified names are used to identify the module and the
structure is flattened out. Each module has the following fields:
    * ```sequence```: This is the sequential version number for the module.
    * ```type_aliases```: Sequential version number for each type alias.
    * ```union_types```: Sequential version number for each union type.
    * ```value_types```: Sequential version number for each value (function) type.
    * ```values```: Sequential version number for each value (function).

Here's an example:

```javascript
{
  "package": "foo/bar"
  "semantic": "2.0.3",
  "sequence": 12,
  "modules": {
    "foo.bar.baz": {
      "sequence": 3,
      "type_aliases": {
        "foo": 3
      },
      "union_types": {
        "bar": 0
      },
      "value_types": {
        "baz": 1
      },
      "values": {
        "baz": 3
      }
    },
    "foo.bar": {
      "sequence": 4,
      "type_aliases": {},
      "union_types": {},
      "value_types": {
        "fizz": 0,
        "fuzz": 1
      },
      "values": {
        "fizz": 0,
        "fuzz": 2
      }
    }
  }
}
```
