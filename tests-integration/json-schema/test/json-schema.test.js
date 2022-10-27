/*
    This file contains the automated tests for the JsonSchema backend.
    It runs the make command to generate the IR from the Morphir models
    Then it runs the gen command to generate the Json Schema.
    The ajv library https://www.npmjs.com/package/ajv  is used to validate the generate json schema
    and instances of the subschemas.
*/
// Imports
const ajv2020 = require("ajv/dist/2020")
const fs = require('fs')
const util = require('util')
const cli = require('../../../cli/cli')

// Variables
const basePath = "tests-integration/json-schema/model/"
const schemaBasePath = "tests-integration/generated/jsonSchema/"
const cliOptions = { typesOnly: false }
const writeFile = util.promisify(fs.writeFile)
var jsonObject
const options = {
    target : 'JsonSchema',
}


describe('Test Suite for Basic Types and Decimal',  () => {

    beforeAll(async () => {
        //Clear generated schema directory
        fs.rmSync(schemaBasePath, {recursive: true, force : true})

        //Create and write IR to file
        const IR =  await cli.make(basePath, cliOptions)
		await writeFile(basePath + 'morphir-ir.json', JSON.stringify(IR))

        // Generate the Json schema
        await cli.gen(basePath + 'morphir-ir.json', schemaBasePath , options)
        const schemaPath = schemaBasePath + "TestModel.json"

        // Read json into an object
        const jsonBuffer = fs.readFileSync(schemaPath, 'utf8')
        jsonObject = JSON.parse(jsonBuffer)
	})

    test("0. Do your thing", () => {

        const boolSchema = {
          $id: "http://example.com/schemas/schema.json",
          type: "object",
          properties: {
            foo: {$ref: "defs.json#/definitions/CollectionTypes.Department"},
          },
        }

        const defsSchema = {
          $id: "http://example.com/schemas/defs.json",
          definitions: jsonObject["$defs"],
        }

        const ajv = new ajv2020({schemas: [boolSchema, defsSchema]})
        const validate = ajv.getSchema("http://example.com/schemas/schema.json")
    })

    test.skip('1. Bool type test case', () => {
        const mainSchema = jsonObject

        const boolSchema= {
            "$id" : "bool1",
            "type": "object",
            "properties": {
                "bool": {
                    "$ref": "#/$defs/BasicTypes.Paid"
                }
            },
            "$defs": mainSchema["$defs"]
        }
        const ajv = new ajv2020({
            schemas: [boolSchema, mainSchema]
        })
        const validate = ajv.getSchema("bool1")


        const result = validate({bool:true})
        expect(result).toBe(true)
    })

    test.skip('2. Int type test case', () => {
        const intSchema = {
           "type": "object",
            "properties": {
                "int": jsonObject["$defs"]["BasicTypes.Age"]
            }
        }
        expect(validator(intSchema, 67)).toBe(true)
    })

    test('3. Float type test case', () => {
        const floatSchema = {
            "type": "number"
        }
        expect(validator(floatSchema, 99.5)).toBe(true)
    })

    test('4. Char type test case', () => {
        const charSchema = {
            "type": "string"
        }
        expect(validator(charSchema, 'A')).toBe(true)
    })

    test('5. String type test case', () => {
        const stringSchema = {
            "type": "string"
        }
        expect(validator(stringSchema, "Baz")).toBe(true)
    })
})

describe('Test Suite for Advanced Types', () => {
    test('1. Test for Decimal type', () => {
        const decimalSchema = {
            "type": "string"
        }
        expect(validator(decimalSchema, "56.34")).toBe(true)
    })

    test.skip('2. Test for LocalDate type', () => {
    })

    test.skip('3. Test for LocalTime type', () => {
    })

    test.skip('4. Test for Month type', () => {
    })
})

describe('Test Suite for Optional Types', () => {
    test.skip('Test for MayBe String', () => {
        const optionalSchema = jsonObject["$defs"]["OptionalTypes.Assignment"]
        expect(validator(optionalSchema, "Foo")).toBe(true)
    })
})

describe('Test Suite for Collection Types', () => {
    test('Test for List type', () => {
        const listSchema = jsonObject["$defs"]["CollectionTypes.Department"]
        expect(validator(listSchema, ["Foo", "Bam", "Baz"])).toBe(true)
    })

    test('Test for Set type', () => {
        const setSchema = jsonObject["$defs"]["CollectionTypes.Queries"]
        expect(validator(setSchema, ["Foo", "Bam"])).toBe(true)
    })

    test.skip('Test for Dict type', () => {
    })
})

describe('Test Suite for Result Types', () => {
    test.skip('Test for  type', () => {
    })
})

describe('Test Suite for Composite Types - Records/Tuples', () => {
    test.skip('Test for Tuple  type', () => {
    })

    test('Test for Record type', () => {
        const recordSchema = jsonObject["$defs"]["RecordTypes.Address"]
        const recordInstance = {
            domainName : "Foo",
            path : "Bar",
            protocol : "http"
        }
        expect(validator(recordSchema, recordInstance)).toBe(true)
    })

    test.skip('Test for Tuple type', () => {
    })
})

describe('Test Suite for Composite Types - Custom Types', () => {
    test('Test for Enum Type', () => {
        const enumSchema = jsonObject["$defs"]["CustomTypes.Currencies"]
        expect(validator(enumSchema, "EUR")).toBe(true)
    })

    test('Test for Custom type 1',  () => {
        const custom1Schema = jsonObject["$defs"]["CustomTypes.Person"]
        expect(validator(custom1Schema, ["Child", "Bar", 11])).toBe(true)
    })

    test('Test for Custom type 2',  () => {
        const custom2Schema = jsonObject["$defs"]["CustomTypes.Person"]
        expect(validator(custom2Schema, ["Adult", "Bar"])).toBe(true)
    })
})

const validator = (schema, instance) => {
    const ajv = new ajv2020()
    const validate = ajv.compile(schema)
    return validate( instance);
}
