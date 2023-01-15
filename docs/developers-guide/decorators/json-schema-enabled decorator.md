# The json-schema-enabled Decorator
This document explains how the json-schema-enabled decorator works and how it is applied to:
* values
* types
* modules
It also explains how a Json Schema is generated based on the annotation

## Overview of json-schema-enabled Decorator
The json-schema-enabled decorator is modeled as a boolean type in the JsonSchema module in the
Attribute model.
When a json-schema-enabled decorator value of true is applied to a type or module, then json-schema
backend code generation would be based on these. 
When applied to a type or value, the fully qualified name is used as the key in the attributed dictionary.
But when applied to a module, the module name is used as the key
All decorator configurations for a project are place in the attributes-conf.json file placed next to the main IR.

## Custom Configuration Modeling
The Custom Attribute configuration model is found in the [CustomAttributes](../../../src/Morphir/CustomAttribute) directory.
The main types of for the decorator configuration model are the CustomAttributeId,
the CustomAttributeConfig, the CustomAttributesConfigs, the CustomAttributesInfo
and the CustomAttributesDetails
* CustomAttributeId - a string type that represents the unique id of the decorator
* CustomAttributeConfig - a record type with one field: filePath which is of type FilePath and represents the attributes-conf.json file
* CustomAttributesConfigs - dictionary of all CustomAttributeConfigs keyed by the CustomAttributeID
* CustomAttributeInfo - dictionary of CustomAttributeInfo keyed by the CustomAttributesId
* CustomAttributeDetails - a record type of with the following fields:
  * displayName - String display name of  the custom attribute
  * entryPoint - FQName or ModuleName being decorated
  * iR - Distribution for the custom attribute IR
  * data - the custom attribute dictionary (content of the <unique-id.json> file)

## Setting Up json-schema-enabled for a New Project
This section explains how the json-schema-enabled decorator is setup for a Morphir project
### Scenario 1
Decorator setup for a project without existing decorator(s)
Follow the steps below to add json-schema-enabled decorator to a Morphir project.
**Step 1** - Create the attributes-conf.json file next to the main IR. Enter the record for the 
json-schema-enabled decorator as shown below

```json
{
	"json-schema-enabled":  {
		"displayName" : "SchemaEnabled"
		, "entryPoint" : "<PackageName>:JsonSchema:SchemaEnabled"
		, "ir" : "attributemodel/morphir-ir.json"
	}
}
```

**Step 2** - Create a new Morphir model in next to the existing IR. This model would contain a single
module named JsonSchema with the SchemaEnabled type defined. This model is place in attributes model folder
**Step 3** - Run the make command on the attributes model to generate the attributes IR
**Step 4 (Optional)** - Create the attributes folder next to the main IR. Inside the folder, create the
json-schema-enabled.json file (the attributes dictionary). Leave it empty
**Step 5** - Start the Develop UI app. The select and type, value or module. Tab to the Custom Attributes tab
and apply the json-schema-enabled  by selecting one of the options (yes/no)
**Step 6** - Run the morphir json-schema-gen command to generate the Json Schema

### Scenario 2 
Decorator setup for a project with existing decorator(s)
**Step 1** - Open the custom-attributes.conf.json and add a new record for the new decorator
**Step 2** - Update the attributes model to include the new decorator type (either on the same or a new module)
**Step 3** - Run the make command to generate your updated IR
Steps 4 to 6 remains the same


## Decorator Configuration Processing - JavaScript
This section explains how decorator configuration is processed and attached to types, values and modules in 
the main IR.
Processing on the decorator configuration begins with the launch of the Develop app.
The decorator configuration records are read from the attributes-conf.json file and processed record by record.
The decorator-conf.json file is key by a unque-id. The value is a an object with three properties:
* displayName: the display name of the decorator
* entryPoint: the FQName or ModuleName it applies to
* ir: filepath to the decorator IR

For each record:
retrieve the custom attributed dictionary by reading which is in a file name with the unique-id of the attribute
using the path field of the record, retrieve the IR of the current custom attribute
Build the decorator details which has four fields:
* displayName
* entryPoint
* data
* iR

A simple API is created that exposes the processed decorator configuration. This is avaialble via the 
`/server/attributes` route.

## Decorator Configuration Processing - Elm
The Morphir Develop app makes a HTTP call to the decorator URL to fetch all the decorators. This is then decoded
into CustomAttributeConfigs which is dictionary of CustomAttributeId and CustomAttributeConfig which is a 
dictionary of CustomAttributeId and CustomAttributeDetails.
These are then displayed in the UI using Morphir ValueEditors.
