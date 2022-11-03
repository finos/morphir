/*
    This file contains the automated tests for the JsonSchema backend.
    It runs the make command to generate the IR from the Morphir models
    Then it runs the gen command to generate the Json Schema.
    The ajv library https://www.npmjs.com/package/ajv  is used to validate the generate json schema
    and instances of the subschemas.
*/
// Imports
const ajv2020 = require("ajv/dist/2020")
const addFormats = require("ajv-formats")
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

    test('1. Bool type test case', () => {
        const boolSchema= {
            "type": "object",
            "properties": {
                "bool": {
                    "$ref": "https://morphir.finos.org/test_model.schema.json#/$defs/BasicTypes.Paid"
                }
            },
        }
        expect(validateBasicType(boolSchema, {bool:true})).toBe(true)
    })

    test('2. Int type test case', () => {
        const intSchema = {
           "type": "object",
            "properties": {
                "int": {
                    "$ref": "https://morphir.finos.org/test_model.schema.json#/$defs/BasicTypes.Age"
                }
            }
        }
        expect(validateBasicType(intSchema, {int: 67})).toBe(true)
    })

    test('3. Float type test case', () => {
        const floatSchema = {
           "type": "object",
            "properties": {
                "float": {
                    "$ref": "https://morphir.finos.org/test_model.schema.json#/$defs/BasicTypes.Score"
                }
            }
        }
        expect(validateBasicType(floatSchema, {float: 93.4})).toBe(true)
    })

    test('4. Char type test case', () => {
        const charSchema = {
           "type": "object",
            "properties": {
                "char": {
                    "$ref": "https://morphir.finos.org/test_model.schema.json#/$defs/BasicTypes.Grade"
                }
            }
        }
        expect(validateBasicType(charSchema, {char: 'A'})).toBe(true)
    })

    test('5. String type test case', () => {
        const stringSchema = {
           "type": "object",
            "properties": {
                "string": {
                    "$ref": "https://morphir.finos.org/test_model.schema.json#/$defs/BasicTypes.Fullname"
                }
            }
        }
        expect(validateBasicType(stringSchema, {string: "Foo"})).toBe(true)
    })
})

describe('Test Suite for Advanced Types', () => {

    test('1. Test for Decimal type', () => {
        const decimalSchema = {
           "type": "object",
            "properties": {
                "decimal": {
                    "$ref": "https://morphir.finos.org/test_model.schema.json#/$defs/AdvancedTypes.Score"
                }
            }
        }
        expect(validateBasicType(decimalSchema, {decimal: "78.9"})).toBe(true)
    })

    test('2. Test for LocalDate type', () => {
            const localDateSchema = {
                "type": "object",
                "properties": {
                    "decimal": {
                        "$ref": "https://morphir.finos.org/test_model.schema.json#/$defs/AdvancedTypes.AcquisitionDate"
                    }
                }
            }
            expect(validateBasicType(localDateSchema, {localDate: "2022-02-02"})).toBe(true)
    })

    test('3. Test for LocalTime type', () => {
            const localTimeSchema = {
                "type": "object",
                "properties": {
                    "localTime": {
                        "$ref": "https://morphir.finos.org/test_model.schema.json#/$defs/AdvancedTypes.EntryTime"
                    }
                }
            }
            expect(validateBasicType(localTimeSchema, {localTime: "20:20:39+00:00"})).toBe(true)
    })

    test('4. Test for Month type', () => {
            const monthSchema = {
                "type": "object",
                "properties": {
                    "month": {
                        "$ref": "https://morphir.finos.org/test_model.schema.json#/$defs/AdvancedTypes.StartMonth"
                    }
                }
            }
            expect(validateBasicType(monthSchema, {month: "78.9"})).toBe(true)
    })
})

describe('Test Suite for Optional Types', () => {
    test('Test for MayBe String', () => {
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

//For validation of Basic Types References the main schema which is JsonObject
const validateBasicType = (schema, instance) => {
    const ajv = new ajv2020()
    addFormats(ajv)
    const validate = ajv.addSchema(jsonObject).compile(schema)
    return validate(instance)
}
