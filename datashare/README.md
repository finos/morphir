# Data Sharing
This project provides a specification for sharing datasets across systems.  It defines:

* A core API for defining datasets and elements via a JSON Schema.
* A mechanism to augment the core by defining more metadata for JSON Schema.
* A standard for linking metadata sets into a graph with JSON-LD
* A standard for packaging and publishing core data sharing metadata.
* An open mechanism to query the metadata graph with GraphQL.

With the combinations of these technologies, we can define strongly typed schemas for collecting sets of metadata (JSON Schema) while also providing complete flexibility to augment with new sets of metadata whenever and wherever needed to create a loosely-coupled graph (JSON-LD). Then we can pull it all together in a structured way with GraphQL.

## Specification
* *API* - The specification for the structure of core dataset and element metadta is defined in [Data.schema.json](src/Data.schema.json).

* *Graph* - The JSON-LD context for utilizing RDF with those structures is defined in [Data.ld.json](src/Data.ld.json).

* *Query* - The GraphQL definition for querying a package of datasets and elements is in [Data.schema.graphql](src/Data.schema.graphql).

* *Runtime* - The tool for querying a package of published datasets is [graphql_server.js](graphql_server.js)/

## Example
An example can be found in the [data folder](data). Some things to look for are:

* *URNs*: Uses URNs to identify Elements and Datasets.
* *File and folder standards*: Metadata sets are defined in their own files with the naming convention of `[name].[metadata set].json`. They sit in a folder structured with path matching the domain. So for the core, we have:
   * Element as `[element name].element.json`
   * Dataset as `[dataset name].dataset.json`
   * ElementInfo - Augments Element as `[element name].element_info.json`. It sits in the folder alongside the Element.
* *GraphQL Resolvers*: The GraphQL server uses special resolvers to inflate the graph using these standards.
  * The resolvers can handle either embeded objects or references that follow the naming convention. So, for example, the Element property of a Dataset field can either refer to one of the existing elements or define an entirely new Element and ElementInfo embedded in the Field. In this case, it sets the URN to `[dataset urn]#[name]`. You can see an example of this in the [`foo` field of the `users` dataset](data/person/users.dataset.json).
* *Flexible autogen vs manual with resolvers*: Sometimes all of the info is not available at generation and needs to be updated manually. Special resolvers allow these to be managed in separate files using the URNs. 
    * *Incomplete Field*: A good example is the [`unknownElementField` in the `zeta` dataset](data/person/zeta%23unknownElementField.element.json), which demonstrates specifying the `element_type` property in a separate file from the dataset definition.
    * *Field Override*: The settings for [`id` in the `zeta` dataset](data/person/zeta.dataset.json) are completely overwritten by an override file [`zeta#id.field.json`](data/person/zeta%23id.field.json).
    * *Unknown Element*: As a fallback, Fields are set to element Nil if they are empty. This allows the GraphQL query to work while giving feedback about which Fields are invalid.

### Running the examples
* Clone the project
* Ensure `node` and `npm` are installed.
* Run `npm install`
* Run the Request Process
  * `node src/request_processor.js` --baseDir data
  * `curl -X POST -H "Content-Type: application/json" -d @test.foo.element.json http://localhost:3000/element`
  * `curl -X POST -H "Content-Type: application/json" -d @test.foo.dataset.json http://localhost:3000/element`
* Run Query Processor
  * `node src/graphql_server.js` --baseDir data
  * Open a browser to the written link.
  * Execute any of the [sample queries](example_graphql_queries.json).


## TODO
* Define the standard for packaging and publishing.
* Define the standard for importing and depending on other packages.
* Demonstrate how teams can use this information to automate much of the required development process.
* Define the API to affect changes to the metadata.
* Implement the implementation of the API for the file-based layout.
* Documenation and diagrams
* GraphQL Federation demo
* JSON-LD/RDF demo
