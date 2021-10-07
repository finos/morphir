// `tsc` should report 3 compile errors for this file.

import type { FooBarBazRecord } from '../generated/refModel/src/typescript/morphir/reference/model/Types'

const badRecord_WrongTypes: FooBarBazRecord = {
    Foo: -1,
    Bar: true,
    Baz: -1,
}

const badRecord_MissingField: FooBarBazRecord = {
    Foo: "Where is Bar?",
    Baz: 0,
}

const badRecord_ExtraField: FooBarBazRecord = {
    Foo: "A delicious banana",
    Bar: true,
    Baz: 123.456,
    Xyzzy: "Plugh",
}
