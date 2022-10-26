/*
    This file contains the automated tests for the JsonSchema backend.
    It runs the make command to generate the IR from the Morphir models
    Then it runs the gen command to generate the Json Schema.
    The ajv library https://www.npmjs.com/package/ajv  is used to validate the generate json schema
    and instances of the subschemas.
*/

const Ajv2020 = require("ajv/dist/2020")
const fs = require('fs')
const basePath = "tests-integration/json-schema/model/"
const schemaBasePath = "tests-integration/generated/jsonSchema/"
const cli = require('../../../cli/cli')
const CLI_OPTIONS = { typesOnly: false }
const util = require('util')
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
        const IR =  await cli.make(basePath, CLI_OPTIONS)
		await writeFile(basePath + 'morphir-ir.json', JSON.stringify(IR))

        // Generate the Json schema
        await cli.gen(basePath + 'morphir-ir.json', schemaBasePath , options)
        const schemaPath = schemaBasePath + "TestModel.json"

        // Read json into an object
        const jsonBuffer = fs.readFileSync(schemaPath, 'utf8')
        jsonObject = JSON.parse(jsonBuffer)
        jsonString = JSON.stringify(jsonObject, null, 4)

	})

    test('1. Bool type test case', () => {

        const boolSchema= {
            "type": "object",
            "properties": {
                "int": {
                    "$ref" : "#/$defs/BasicTypes.Paid"
                }
            },
            "$defs" : jsonObject["$defs"]
        }


        const ajv = new Ajv2020()
        const validate = ajv.compile(boolSchema)
        const result = validate({bool: true});
        expect(result).toBe(true)
    })


    test.skip('2. Int type test case', () => {
        const intSchema = {
           "type": "object",
            "properties": {
                "int": jsonObject["$defs"]["BasicTypes.Age"]
            }
        }
        const ajv = new Ajv2020({allErrors: true})
        const validate = ajv.compile(intSchema)
        const result = validate({int : 45})
        expect(result).toBe(true)
        console.log(validate.errors)

    })
    test('3. Float type test case', () => {
        const floatSchema = {
            "type": "number"
        }
        const ajv = new Ajv2020()
        const validate = ajv.compile(floatSchema)

        const result = validate(4.5)
        expect(result).toBe(true)
    })
    test('4. Char type test case', () => {
        const charSchema = {
            "type": "string"
        }
        const ajv = new Ajv2020()
        const validate = ajv.compile(charSchema)
        const result = validate('A')
        expect(result).toBe(true)
    })
    test('5. String type test case', () => {
        const stringSchema = {
            "type": "string"
        }
        const ajv = new Ajv2020()
        const validate = ajv.compile(stringSchema)
        const result = validate("Morphir String")
        expect(result).toBe(true)
    })
})

describe('Test Suite for Advanced Types', () => {
    test('1. Test for Decimal type', () => {
        const decimalSchema = {
                            "type": "string"
                           }
        const ajv = new Ajv2020()
        const validate = ajv.compile(decimalSchema)
        const result = validate("99.9")
        expect(result).toBe(true)
    })

    test.skip('2. Test for LocalDate type', () => {
    })

    test.skip('3. Test for LocalTime type', () => {
    })
    
    test.skip('4. Test for Month type', () => {
    })
})

describe('Test Suite for Optional Types', () => {
    test('Test for MayBe String', () => {
        const optionalSchema = jsonObject["$defs"]["OptionalTypes.Assignment"]
        console.log(optionalSchema)
        const ajv = new Ajv2020()
        const validate = ajv.compile(optionalSchema)
        const result = validate("Bar")
        expect(result).toBe(true)
    })
})

describe('Test Suite for Collection Types', () => {
    test('Test for List type', () => {
        const listSchema = jsonObject["$defs"]["CollectionTypes.Department"]
        console.log(listSchema)
        const ajv = new Ajv2020()
        const validate = ajv.compile(listSchema)
        const result = validate(["HR", "IT", "HR"])
        expect(result).toBe(true)

    })
    test('Test for Set type', () => {
        const setSchema = jsonObject["$defs"]["CollectionTypes.Proids"]
        const ajv = new Ajv2020()
        const validate = ajv.compile(setSchema)
        const result = validate(["bsdev", "morphirdev"])
        expect(result).toBe(true)        
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
        const ajv = new Ajv2020()
        const validate = ajv.compile(recordSchema)
        const recordInstance = {
            country : "US",
            state : "New York",
            street : "Devin"
        }
        const result = validate(recordInstance)
        expect(result).toBe(true)
    })

    test.skip('Test for Tuple type', () => {
    })
})

describe('Test Suite for Composite Types - Custom Types', () => {
    test('Test for Enum Type', () => {
        const enumSchema = jsonObject["$defs"]["CustomTypes.Currencies"]
        const ajv = new Ajv2020()
        const validate = ajv.compile(enumSchema)
        const result = validate("USD")
        expect(result).toBe(true)
    })

    test('Test for Custom type 1',  () => {
        const custom1Schema = jsonObject["$defs"]["CustomTypes.Person"]

        const ajv = new Ajv2020()
        const validate = ajv.compile(custom1Schema)
        const result = validate(["Child", "Bar", 11])
        expect(result).toBe(true)
    })

    test('Test for Custom type 2',  () => {
        const custom2Schema = jsonObject["$defs"]["CustomTypes.Person"]
        const ajv = new Ajv2020()
        const validate = ajv.compile(custom2Schema)
        const result = validate( ["Adult", "foo"]);
        expect(result).toBe(true)
    })
})