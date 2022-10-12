const fs = require('fs')
const execSync = require('child_process').execSync;
const basePath = "tests-integration/json-schema/model/"
const schemaBasePath = "tests-integration/generated/jsonSchema/"
const cli = require('../../../cli/cli')
const CLI_OPTIONS = { typesOnly: false }
const util = require('util')
const writeFile = util.promisify(fs.writeFile)

const Validator = require('jsonschema').Validator;
const v = new Validator()
var jsonObject
var jsonBuffer
const options = {
    target : 'JsonSchema',

}

describe('Test Suite for Basic Types',  () => {

    beforeAll(async () => {
        fs.rmSync(schemaBasePath, {recursive: true, force : true})
        
        const IR =  await cli.make(basePath, CLI_OPTIONS)
		await writeFile(basePath + 'morphir-ir.json', JSON.stringify(IR))

        //here
        await cli.gen(basePath + 'morphir-ir.json', schemaBasePath , options)
 
        const schemaPath = schemaBasePath + "TestModel.json"

        jsonBuffer = fs.readFileSync(schemaPath, 'utf8')
        jsonObject = JSON.parse(jsonBuffer)

	})

    test('1. Bool type test case', () => {
        jsonObject["$ref"] = "#/$defs/BasicTypes.Paid"
        const result = v.validate(true, jsonObject)
        expect(result.valid).toBe(true)
    })
    test('2. Int type test case', () => {
        jsonObject["$ref"] = "#/$defs/BasicTypes.Age"
        const result = v.validate(45, jsonObject)
        expect(result.valid).toBe(true)
    })
    test('3. Float type test case', () => {
        jsonObject["$ref"] = "#/$defs/BasicTypes.Score"
        const result = v.validate(4.5, jsonObject)
        expect(result.valid).toBe(true)
    })
    test('4. Char type test case', () => {
        jsonObject["$ref"] = "#/$defs/BasicTypes.Grade"
        const result = v.validate('A', jsonObject)
        expect(result.valid).toBe(true)
    })
    test('5. String type test case', () => {
        jsonObject["$ref"] = "#/$defs/BasicTypes.Fullname"
        const result = v.validate("Morphir String", jsonObject)
        expect(result.valid).toBe(true)
    })
})

describe('Test Suite for Advanced Types', () => {
    test('1. Test for Decimal type', () => {
        jsonObject["$ref"] = "#/$defs/AdvancedTypes.Score"
        var result = v.validate("99.9", jsonObject)
        expect(result.valid).toBe(true)
    })
    test.skip('2. Test for LocalDate type', () => {
        jsonObject["$ref"] = "#/$defs/AdvancedTypes.StartTime"

    })
    test.skip('3. Test for LocalTime type', () => {
        jsonObject["$ref"] = "#/$defs/AdvancedTypes.StartTime"

    })
    test.skip('4. Test for Month type', () => {
        jsonObject["$ref"] = "#/$defs/AdvancedTypes.Month"

    })
})

describe('Test Suite for Optional Types', () => {
    test('Test for MayBe type', () => {
        jsonObject["$ref"] = "#/$defs/OptionalTypes.Assignment"
        var result = v.validate('Bar', jsonObject)
        expect(result.valid).toBe(true)
    })
})

describe('Test Suite for Collection Types', () => {
    test('Test for List type', () => {
        jsonObject["$ref"] = "#/$defs/OptionalTypes.Assignment"

    })
    test('Test for Set type', () => {
        jsonObject["$ref"] = "#/$defs/OptionalTypes.Assignment"

    })
    test('Test for Dict type', () => {
        jsonObject["$ref"] = "#/$defs/OptionalTypes.Assignment"

    })
})

describe('Test Suite for Result Types', () => {
    test('Test for  type', () => {
        jsonObject["$ref"] = "#/$defs/OptionalTypes.Assignment"

    })
})


describe('Test Suite for Composite Types', () => {
    test('Test for Tuple  type', () => {
        jsonObject["$ref"] = "#/$defs/OptionalTypes.Assignment"

    })
})