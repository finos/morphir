const assert = require('assert');

import { Morphir } from '../generated/refModel/src/typescript/Morphir'

// Tests for generated TypeScript API, using types from reference-model.
//
// We are testing TypeScript types so bugs in the generated code will
// mostly appear as compile failures, rather than runtime assert failures.
describe('TypeScript type mapping', function() {
    it('represents custom type variants', function() {
        const goodNoArg: Morphir.Reference.Model.Types.Custom = { kind: "CustomNoArg" };
        const goodOneArg: Morphir.Reference.Model.Types.Custom = { kind: "CustomOneArg", arg1: true };
        const goodTwoArg: Morphir.Reference.Model.Types.Custom = { kind: "CustomTwoArg", arg1: "some good quantity", arg2: 42 };

        // The `kind` field must be specified even when we specify the variant explicitly.
        const goodNoArg_Explicit: Morphir.Reference.Model.Types.CustomNoArg = { kind: "CustomNoArg" };
        const goodOneArg_Explicit: Morphir.Reference.Model.Types.CustomOneArg = { kind: "CustomOneArg", arg1: true };
        const goodTwoArg_Explicit: Morphir.Reference.Model.Types.CustomTwoArg = { kind: "CustomTwoArg", arg1: "some good quantity", arg2: 42 };

        assert.equal(goodNoArg.kind, "CustomNoArg");
        assert.equal(goodNoArg_Explicit.kind, "CustomNoArg");
    })

    it('represents custom type unions', function() {
        const goodNoArg: Morphir.Reference.Model.Types.Custom = { kind: "CustomNoArg" };
        const goodOneArg: Morphir.Reference.Model.Types.Custom = { kind: "CustomOneArg", arg1: true };
        const goodTwoArg: Morphir.Reference.Model.Types.Custom = { kind: "CustomTwoArg", arg1: "some good quantity", arg2: 42 };

        const goodVariantArray: Morphir.Reference.Model.Types.Custom[] = [
            goodNoArg, goodOneArg, goodTwoArg,
        ];
    })

    it('allows constructing custom types', function() {
        // This is rather ugly. Adding constructor functions might help, e.g.:
        //
        //     const goodFullName = FullName(FirstName("Brian"), LastName("Blessed"));
        //
        const fullName_Manual: Morphir.Reference.Model.Types.FullName = {
            kind: "FullName",
            arg1: {
                kind: "FirstName",
                arg1: "Brian"
            },
            arg2: {
                kind: "LastName",
                arg1: "Blessed"
            }
        };

        const fullName_ConstructorFn = new Morphir.Reference.Model.Types.FullName(
            new Morphir.Reference.Model.Types.FirstName("Brian"),
            new Morphir.Reference.Model.Types.LastName("Blessed"),
        );

        assert.deepEqual(fullName_Manual, fullName_ConstructorFn);
    })

    it('allows constructing records', function() {
        const goodRecord: Morphir.Reference.Model.Types.FooBarBazRecord = {
            foo: "A delicious banana",
            bar: true,
            baz: 123.456,
        }
    })
})
