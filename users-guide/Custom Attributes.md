# Custom attributes user guide
The contents of this document detail how to structure and load optional "sidecar" files for the purposes of adding custom attributes to Morphir types and values. Custom attributes can assign extra information to business concepts that is otherwise not included in the Morphir IR.

**Contents:**
- [File format and naming convention](#file-format-and-naming-convention)
	 - [Config file](#config-file)
	 - [Attribute file](#attribute-file)
- [Loading and updating the attribute files](#loading-and-updating-the-attribute-files)




## File format, and naming convention
To define a custom attribute, we need at least three JSON files. 

 1. A config file named `attribute.conf.json` that lists the attribute ID's, and maps them to display names.
 2. At least one attribute file named `<someAttributeId>.json` in the `attributes`.
 3. An IR containing a type definitions 
 
### Config file
```
{
	"test-id-1":  {
		"displayName" : "MS.Sensitivity"
		, "entryPoint" : "Morphir.Attribute.Model.Sensitivity.Sensitivity"
		, "ir" : "attributes/sensitivity.ir.json"
	}
	"test-id-2":  {
		...
	}
}
```
The above example is a sample config file structure. The config file should contain key-value pairs in a JSON format, where the key is the attribute name, and the value is the attribute description. 
The attribute description should include an entrypoint in the form of an [FQName](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir.IR.FQName) (this is the type describing your custom attribute), a display name, and a path to the IR file containing your type model

### Attribute file
```
{
	"Morphir.Reference.Model.Issues.Issue401:bar": {
		"MNPI": false,
		"PII": true
	},
	 "Morphir.Reference.Model.Issues.Issue401:foo": {
		"MNPI": false,
		"PII": false
	}
}
```
The above example is a sample attribute file structure. The attribute file should be a dictionary in a JSON  format, where the keys are Morphir [FQName](https://package.elm-lang.org/packages/finos/morphir-elm/latest/Morphir.IR.FQName)s, and the values are any valid JSON object.


## Loading and updating the attribute files
We currently provide the following APIs.

***GET /server/attributes/***
Returns the a JSON file with a very similar structure to the config file, but amended with `data` fields containing the actual custom attribute values, and the `ir` field containing the actual IR instead of a path pointing to it

```
{
	"test-id-1":  {
		"displayName" : <displayName>
		, "entryPoint" : <FQName>
		, "ir" : "<a Morphir IR>"
		, "data" : <custom attribute dictionary>
	}
	"test-id-2":  {
		...
	}
}
```

***POST /server/updateattribute/\<yourattributename>***
```
{ 
	"nodeId" : <fqname>,
	"newAttribute: <JSON>
}
```
Updates the given node with the given new attribute.