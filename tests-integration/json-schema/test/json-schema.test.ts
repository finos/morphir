const fs = require('fs')
const execSync = require('child_process').execSync;
const basePath = "tests-integration/json-schema/model/"


execSync('morphir-elm make', {encoding: 'utf-8', cwd: basePath})
execSync('morphir-elm gen -t JsonSchema', {encoding: 'utf-8', cwd: basePath})
console.log(basePath)



const schemaPath = basePath + "dist/TestModel.json"
const jsonBuffer = fs.readFileSync(schemaPath, 'utf8')
const jsonObject = JSON.parse(jsonBuffer)
const Validator = require('jsonschema').Validator;
const v = new Validator()

describe('Test Suite for Basic Types', () => {

    test('1. Bool type test case', () => {
        jsonObject["$ref"] = "#/$defs/BasicTypes.Paid"
        var result = v.validate(true, jsonObject)
        expect(result.valid).toBe(true)
    })
    test('2. Int type test case', () => {
        jsonObject["$ref"] = "#/$defs/BasicTypes.Age"
        var result = v.validate(45, jsonObject)
        expect(result.valid).toBe(true)
    })
    test('3. Float type test case', () => {
        jsonObject["$ref"] = "#/$defs/BasicTypes.Score"
        var result = v.validate(4.5, jsonObject)
        expect(result.valid).toBe(true)
    })
    test('4. Char type test case', () => {
        jsonObject["$ref"] = "#/$defs/BasicTypes.Grade"
        var result = v.validate('A', jsonObject)
        expect(result.valid).toBe(true)
    })
    test('5. String type test case', () => {
        jsonObject["$ref"] = "#/$defs/BasicTypes.Fullname"
        var result = v.validate("Morphir String", jsonObject)
        expect(result.valid).toBe(true)
    })
})

describe('Test Suite for Advanced Types', () => {
    test('1. Test for Decimal type', () => {
        jsonObject["$ref"] = "#/$defs/AdvancedTypes.Score"
        var result = v.validate("99.9", jsonObject)
        expect(result.valid).toBe(true)
    })
    test('2. Test for LocalDate type', () => {
        jsonObject["$ref"] = "#/$defs/AdvancedTypes.StartTime"

    })
    test('3. Test for LocalTime type', () => {
        jsonObject["$ref"] = "#/$defs/AdvancedTypes.StartTime"

    })
    test('4. Test for Month type', () => {
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
    test('Test for MayBe type', () => {
        jsonObject["$ref"] = "#/$defs/OptionalTypes.Assignment"

    })

})