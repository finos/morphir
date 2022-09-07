# Custom attributes user guide
The contents of this document detail how to structure and load optional "sidecar" files for the purposes of adding custom attributes to Morphir types and values. Custom attributes can assign extra information to business concepts that is otherwise not included in the Morphir IR.

**Contents:**
- [File format and naming convention](#file-format-and-naming-convention)
	 - [Config file](#config-file)
	 - [Attribute file](#attribute-file)
- [Loading and updating the attribute files](#loading-and-updating-the-attribute-files)




## File format, and naming convention
To define a custom attribute, we need at least two JSON files. 

 1. A config file named `attribute.conf.json` that lists the attribute ID's, and maps them to display names.
 2. At least one attribute file named `<someAttributeId>.json` in the `attributes` folder next to where the IR is located.
 
### Config file
```
{
	"test-id-1":  {
		"displayName" : "test Name"
	},
	"test-id-2":  {
		"displayName" : "Second Test Name"
	}
}
```
The above example is a sample config file structure. The config file should contain key-value pairs in a JSON format, where the key is the attribute name, and the value is the attribute description.

### Attribute file
```
{
	"Morphir.Reference.Model.Issues.Issue401:bar": {
		"MMPI": false
	},
	 "Morphir.Reference.Model.Issues.Issue401:foo": {
		"MMPI": false
	}
}
```
The above example is a sample attribute file structure. The attribute file should be a dictionary in a JSON  format, where the keys are Morphir [FQName](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir.IR.FQName)s, and the values are any valid JSON object.


## Loading and updating the attribute files
We currently provide the following APIs.

***GET /server/attributes/***
Returns the a JSON file with key-value pairs of attribute display names, and the contents of the corresponding attribute file.


***POST /server/updateattribute/\<yourattributename>***
```
{ 
	"nodeId" : <fqname>,
	"newAttribute: <JSON>
}
```
Updates the given node with the given new attribute.