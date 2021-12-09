const assert = require('assert');

import { Morphir } from '../generated/morphirIR/src/typescript/Morphir'
import * as codecs from "../generated/morphirIR/src/typescript/morphir/internal/Codecs"

const fs = require('fs')
const util = require('util')
const readFile = util.promisify(fs.readFile);

const INPUT = 'tests-integration/generated/morphirIR/morphir-ir.json'

describe('JSON codec', function() {
    it('should roundtrip List and Tuple instances correctly', function() {
        let example: Morphir.IR.FQName.FQName = [
            [ [ "Excellent" ], [ "Package" ] ],
            [ [ "Fantastic" ], [ "Module" ] ],
            [ "Amazing", "Local", "Name" ]
        ]

        let encoded = Morphir.IR.FQName.encodeFQName(example);
        // Tuples and Lists encode to JSON without changes.
        assert.deepEqual(encoded, example);

        let decoded = Morphir.IR.FQName.decodeFQName(encoded);
        assert.deepEqual(decoded, example);
    })

    it('should roundtrip Record and Dict instances correctly', function() {
        let accessPublic = new Morphir.IR.AccessControlled.Public();

        let upName: Morphir.IR.Name.Name = ["up"]

        let upConstructor: Morphir.IR.Type.Constructors<[]> = new Map([
            [upName, []]
        ])

        let directionAccessControlled: Morphir.IR.AccessControlled.AccessControlled<Morphir.IR.Type.Constructors<[]>> = {
            access: accessPublic,
            value: upConstructor
        }

        let encoded = Morphir.IR.AccessControlled.encodeAccessControlled(
            Morphir.IR.Type.encodeConstructors.bind(null, codecs.encodeUnit),
            directionAccessControlled);

        let decoded = Morphir.IR.AccessControlled.decodeAccessControlled(
            Morphir.IR.Type.decodeConstructors.bind(null, codecs.encodeUnit),
            encoded);

        assert.deepEqual(decoded, directionAccessControlled);
    })

    it('should roundtrip `morphir-ir.json` correctly', function() {
        return readFile(INPUT)
            .then(buffer => {
                const data = JSON.parse(buffer);
                const distribution = data['distribution'];

                const decoded = Morphir.IR.Distribution.decodeDistribution(distribution);

                const encoded = {
                    formatVersion: 2,
                    distribution: Morphir.IR.Distribution.encodeDistribution(decoded),
                }
                assert.deepEqual(data, encoded);
            });
    })
})
