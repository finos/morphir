import Ajv2020 from "../../../node_modules/ajv/dist/2020"
const ajv = new Ajv2020()
const fs = require('fs')
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
        //Clear generated schema directory
        fs.rmSync(schemaBasePath, {recursive: true, force : true})

        //Create and write IR
        const IR =  await cli.make(basePath, CLI_OPTIONS)
		await writeFile(basePath + 'morphir-ir.json', JSON.stringify(IR))

        // Generate the schema
        await cli.gen(basePath + 'morphir-ir.json', schemaBasePath , options)
        const schemaPath = schemaBasePath + "TestModel.json"

        // Read json into an object
        jsonBuffer = fs.readFileSync(schemaPath, 'utf8')
        jsonObject = JSON.parse(jsonBuffer)

	})

    test('1. Bool type test case', () => {
        jsonObject["$ref"] = "#/$defs/BasicTypes.Paid"
        jsonObject["$id"] = "#"
        const validate = ajv.compile(jsonObject)
        const result = validate(true);
        expect(result).toBe(true)
    })
    // test('2. Int type test case', () => {
    //     jsonObject["$ref"] = "#/$defs/BasicTypes.Age"
    //     const result = v.validate(45, jsonObject)
    //     expect(result.valid).toBe(true)
    // })
    // test('3. Float type test case', () => {
    //     jsonObject["$ref"] = "#/$defs/BasicTypes.Score"
    //     const result = v.validate(4.5, jsonObject)
    //     expect(result.valid).toBe(true)
    // })
    // test('4. Char type test case', () => {
    //     jsonObject["$ref"] = "#/$defs/BasicTypes.Grade"
    //     const result = v.validate('A', jsonObject)
    //     expect(result.valid).toBe(true)
    // })
    // test('5. String type test case', () => {
    //     jsonObject["$ref"] = "#/$defs/BasicTypes.Fullname"
    //     const result = v.validate("Morphir String", jsonObject)
    //     expect(result.valid).toBe(true)
    // })
})

// describe('Test Suite for Advanced Types', () => {
//     test('1. Test for Decimal type', () => {
//         jsonObject["$ref"] = "#/$defs/AdvancedTypes.Score"
//         const result = v.validate("99.9", jsonObject)
//         expect(result.valid).toBe(true)
//     })
//     test.skip('2. Test for LocalDate type', () => {
//         jsonObject["$ref"] = "#/$defs/AdvancedTypes.StartTime"

//     })
//     test.skip('3. Test for LocalTime type', () => {
//         jsonObject["$ref"] = "#/$defs/AdvancedTypes.StartTime"

//     })
//     test.skip('4. Test for Month type', () => {
//         jsonObject["$ref"] = "#/$defs/AdvancedTypes.Month"

//     })
// })

// describe('Test Suite for Optional Types', () => {
//     test('Test for MayBe type', () => {
//         jsonObject["$ref"] = "#/$defs/OptionalTypes.Assignment"
//         const result = v.validate('Bar', jsonObject)
//         expect(result.valid).toBe(true)
//     })
// })

// describe('Test Suite for Collection Types', () => {
//     test('Test for List type', () => {
//         jsonObject["$ref"] = "#/$defs/CollectionTypes.Department"
//         const result = v.validate(["HR", "IT", "HR"], jsonObject)
//         expect(result.valid).toBe(true)

//     })
//     test('Test for Set type', () => {
//         jsonObject["$ref"] = "#/$defs/CollectionTypes.Proids"
//         const result = v.validate(["bsdev", "morphirdev"], jsonObject)
//         expect(result.valid).toBe(true)        
//     })
//     test.skip('Test for Dict type', () => {
//         jsonObject["$ref"] = "#/$defs/CollectionTypes.Assignment"

//     })
// })

// describe('Test Suite for Result Types', () => {
//     test.skip('Test for  type', () => {
//         jsonObject["$ref"] = "#/$defs/ResultTypes.Assignment"

//     })
// })


// describe('Test Suite for Composite Types - Records/Tuples', () => {
//     test.skip('Test for Tuple  type', () => {
//         jsonObject["$ref"] = "#/$defs/CompositeTypes.Assignment"

//     })
//     test('Test for Record type', () => {
//         jsonObject["$ref"] = "#/$defs/RecordTypes.Address"
//         const recordInstance = {
//             country : "US",
//             state : "New York",
//             street : "Devin"
//         }
//         const result = v.validate(recordInstance, jsonObject)
//         expect(result.valid).toBe(true)
//     })
//     test.skip('Test for Tuple type', () => {
//         jsonObject["$ref"] = "#/$defs/CompositeTypes.Assignment"
        
//     })
// })

// describe('Test Suite for Composite Types - Custom Types', () => {
//     // test('Test for Tuple Enum', () => {
//     //     jsonObject["$ref"] = "#/$defs/CustomTypes.Currencies"
//     //     const result = v.validate("USD", jsonObject)
//     //     expect(result.valid).toBe(true)
//     // })

//     // test.skip('Test for Custom type 1',  () => {
//     //     jsonObject["$ref"] = "#/$defs/CustomTypes.Person"

//     //     const result = v.validate(["Adult", "Foo"], jsonObject, {nestedErrors: true})
//     //     expect(result.valid).toBe(true)
//     // })

//     test('Test for Custom type 2',  () => {
//         jsonObject["$ref"] = "#/$defs/CustomTypes.Person"
//         const validate = ajv.compile(jsonObject)
//         const result = validate( ["Adult", "foo"]);
//         console.log(validate)
//         expect(result).toBe(true)
//     })
// })