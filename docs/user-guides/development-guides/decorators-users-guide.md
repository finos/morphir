---
id: decorations-users-guide
sidebar_position: 12
---

# Decorations User Guide

The Morphir IR contains all the domain models and business logic that you defined in your model but sometimes
you want to add more information that cannot be captured in the language. Decorations provide a way to assign
additional information to any part of the domain model or business logic that is stored in a separate (sidecar) 
file. The shape of the decoration is defined in Morphir as well and stored using the standard JSON serialization 
format that all Morphir tools integrate with.  

Now let's see how you can set them up. This can be done in a few easy steps:

- [Create or find a Decoration Schema](#create-or-find-a-decoration-schema)
- [Set up the decoration for your model](#set-up-the-decoration-for-your-model)
- [Start adding decorations](#start-adding-decorations) 
- [Using the morphir decoration-setup Command](#using-the-morphir-decoration-setup-command)


## Create or find a Decoration Schema

The first thing you will need is a Morphir IR that describes the shape of the decoration. If you want to use an existing 
decoration you just need to make sure you have access to the `morphir-ir.json` for it. If you want to create your own
decoration, you just need to set up another morphir project, define types that describe what you want and generate a 
`morphir-ir.json` using `morphir make`.

## Set up the decoration for your model

Decorations can be configured in the `morphir-ir.json`. The `decorations` field is a simple object where you can list 
out one or more decorations using an arbitrary key (it will only be used as an internal identifier within this project): 

```
{
    "name": "My.Package",
    "sourceDirectory": "src",
    "decorations": {
        "myDecoration": {
            "displayName": "My Amazing Decoration",
            "ir": "decorations/my/morphir-ir.json", 
            "entryPoint": "My.Amazing.Decoration:Foo:Shape",
            "storageLocation": "my-decoration-values.json" 
        }
    }
}
```

Each decoration section should include: 
- a display name which will be used in Morphir Web
- an entry point which is a reference to the type that describes the shape of your decoration
  - this should be in the form of a fully-qualified name with the package name, module name and local name separated by `:`
- a path to the IR file containing your type model
  - the entry point specified above needs to align exactly with the IR specified here so make sure that:
    - the name of the package defined in the `morphir.json` of this IR matches with the first part of the entry point
    - there is a module in the IR that matches the second part of the entry point
    - there is a type in that module that matches the third part of the entry point
- a storage location that specifies where the decoration data will be saved    

## Using the morphir decoration Commands

Morphir provides several CLI commands to manage decorations:

### Setting Up Decorations

#### Using a Registered Type (Recommended)

If you have a decoration type registered in the registry, you can use it directly:

```bash
morphir decoration setup myDecoration --type documentation
```

This automatically configures the decoration using the registered type's IR path and entry point.

#### Using Direct Paths

You can also set up decorations by specifying the IR file and entry point directly:

```bash
morphir decoration setup myDecoration \
  -i decorations/morphir-ir.json \
  -e "My.Amazing.Decoration:Foo:Shape" \
  --display-name "My Amazing Decoration" \
  --storage-location "my-decoration-values.json"
```

### Registering Decoration Types

Before you can use `--type`, you need to register the decoration type:

```bash
morphir decoration type register documentation \
  -i ~/.morphir/decorations/documentation/morphir-ir.json \
  -e "Documentation.Decoration:Types:Documentation" \
  --display-name "Documentation" \
  --description "Add documentation to IR nodes" \
  --global  # Register globally for all projects
```

### Managing Decoration Types

```bash
# List all registered types
morphir decoration type list

# Show details about a type
morphir decoration type show documentation

# Unregister a type
morphir decoration type unregister documentation
```

### Validating Decorations

```bash
# Validate all decorations
morphir decoration validate

# Validate with JSON output
morphir decoration validate --json
```

### Querying Decorations

```bash
# List all decorated nodes
morphir decoration list

# List nodes with specific decoration type
morphir decoration list --type documentation

# Get decorations for a specific node
morphir decoration get "My.Package:Foo:bar"

# Get specific decoration type for a node
morphir decoration get "My.Package:Foo:bar" --type documentation

# Show decoration statistics
morphir decoration stats
```

## Start adding decorations

Once this is all set up you can use Morphir Web to start adding decorations on your model. First you need to run 
`morphir-elm develop` and open a browser at the specified port on localhost. In the UI you will see a "Decorations"
tab on the right as you click through modules/types and values. The tab should display all the decorations you 
specified with editors that allow you to specify values. 

Every edit is saved automatically as you make changes in the file you specified in the config (`storageLocation` field).
If you open the file you should see something like this: 

```
{
	"My.Package:Foo:bar": ...,
	"My.Package:Baz:bat": ...
}
```

It's an object with a node id that identifies the part of the model that you put the decoration on, and a value that
you specified in the UI.

## Decoration Type Registry

The decoration type registry allows you to discover and reuse decoration schemas across projects.

### Registering Types

Register a decoration type once, then use it in any project:

```bash
# Register globally (available to all projects)
morphir decoration type register documentation \
  -i ~/.morphir/decorations/documentation/morphir-ir.json \
  -e "Documentation.Decoration:Types:Documentation" \
  --display-name "Documentation" \
  --global

# Register in workspace (project-specific)
morphir decoration type register myDecoration \
  -i decorations/morphir-ir.json \
  -e "My.Decoration:Types:Shape" \
  --display-name "My Decoration"
```

### Using Registered Types

Once registered, you can reference decoration types by name:

```bash
# Set up decoration using registered type
morphir decoration setup docs --type documentation
```

This is much simpler than specifying IR paths and entry points manually!

### Registry Locations

- **Workspace**: `.morphir/decorations/registry.json` (project-specific)
- **Global**: `~/.morphir/decorations/registry.json` (user-wide)
- **System**: `/etc/morphir/decorations/registry.json` (system-wide)

Workspace registries take precedence over global, which take precedence over system.

## Examples

See the `examples/decorations/` directory for complete working examples:

- `simple-flag/` - A minimal boolean flag decoration
- `documentation/` - A structured documentation decoration

Each example includes:
- Elm source code for the decoration schema
- Configuration files
- Example decoration value files
- README with usage instructions