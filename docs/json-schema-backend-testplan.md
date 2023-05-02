---
id: json-schema-backend-test
title: Backend Test Specification
---

# Json Schema Backend Test Specification
This document speficies the testing strategy for the Json Schema backend.

1. [Unit Tests (Elm)](#unitTests)
2. [System Tests (JavaScript)](#systemTests)
4. [Acceptance Tests (JavaScript)](#3-acceptance-tests-javascript)

### 1. Unit Tests (Elm) 

The unit test aims to test all the ```elm mapType()``` and the ```elm mapTypeDefinition()``` methods defined in the [Json Schema Backend]('../../../src/JsonSchema/Backeng.elm')

Test for each module would be defined in a file with the name pattern &lt;ModuleName&gt; Tests.elm.
For example \
Test for BasicTypes would be  defined in a file named BasicTypesTests.elm

### 2. System Test (JavaScript)

The objective of this test is to ensure that the Json schema generated
by the system is valid.
Therefore this would be implemented using the Jest on the JavaScript end.
The [Ajv Json Schema Validator](https://www.npmjs.com/package/ajv?activeTab=readme) library would be used for validation.

We also need to ensure the validity of each subschema
in the generated Json output.\
This tests are defined in the [json-schema.test.js](../../../tests-integration/json-schema/test/json-schema.test.js) file.
This tests are performed in tandem with the Accetance Tests

### 3. Acceptance Tests  JavaScript
The objective of this test is to ensure that each sub-schema in the generated Json Schema
validates corresponding json document instances of that schema.
This tests are defined in the [json-schema.test.js](../../../tests-integration/json-schema/test/json-schema.test.js) file.
