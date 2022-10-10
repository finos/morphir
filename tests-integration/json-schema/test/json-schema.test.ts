const fs = require('fs')

const schemaPath = "tests-integration/json-schema/model/dist/TestModel.json"

const jsonBuffer = fs.readFileSync(schemaPath, 'utf8')
var jsonObject = JSON.parse(jsonBuffer)
const definitions = jsonObject['$defs']

var Validator = require('jsonschema').Validator;

describe('Testing the Json Schema', () => {

    test('String type test for Arrays.Address schema', () => {
        // We append a reference to the Arrays.Address schema to the root schema
        const addressRef = "{ \"$ref\" : \"#/$defs/Arrays.Address\", \"type\" : \"object\", "
        var addressTestSchema = addressRef.concat (jsonBuffer.substring(1))
        var addressTestInstance = "Croydon street"
        var addressSchema = definitions['Arrays.Address']

        var v = new Validator()
        var result = v.validate(addressTestInstance, addressSchema)
        console.log(result.valid)
    })

    test('Int type test', () => {
       var v = new Validator()
       var instance = 5
       var intSchema
    })
})