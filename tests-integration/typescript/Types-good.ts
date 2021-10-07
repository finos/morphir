// `tsc` should compile this file with no errors.

import { Custom, CustomNoArg, CustomOneArg, CustomTwoArg, FullName, FooBarBazRecord } from '../generated/refModel/src/typescript/morphir/reference/model/Types'

const goodNoArg: Custom = { kind: "CustomNoArg" };
const goodOneArg: Custom = { kind: "CustomOneArg", arg1: true };
const goodTwoArg: Custom = { kind: "CustomTwoArg", arg1: "some good quantity", arg2: 42 };

// The `kind` field must be specified even when we specify the variant explicitly.
const goodNoArg_Explicit: CustomNoArg = { kind: "CustomNoArg" };
const goodOneArg_Explicit: CustomOneArg = { kind: "CustomOneArg", arg1: true };
const goodTwoArg_Explicit: CustomTwoArg = { kind: "CustomTwoArg", arg1: "some good quantity", arg2: 42 };

const goodVariantArray: Custom[] = [
    goodNoArg, goodOneArg, goodTwoArg,
    goodNoArg_Explicit, goodOneArg_Explicit, goodTwoArg_Explicit
];

// This is rather ugly. Adding constructor functions might help, e.g.:
//
//     const goodFullName = FullName(FirstName("Brian"), LastName("Blessed"));
//
const goodFullName = {
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

const goodRecord: FooBarBazRecord = {
    foo: "A delicious banana",
    bar: true,
    baz: 123.456,
}
