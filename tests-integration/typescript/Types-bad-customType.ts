// `tsc` should report 6 compile errors for this file.
//
import type { Custom, CustomOneArg } from '../generated/refModel/src/typescript/morphir/reference/model/Types'

const badNoArg_TooManyArgs: Custom = { kind: "CustomNoArg", arg1: false, arg2: "Very wrong" };
const badNoArg_NoKindField: Custom = {};

const badOneArg_WrongArgType: Custom = { kind: "CustomOneArg", arg1: "This is not a boolean" };

const badTwoArg_MissingArg: Custom = { kind: "CustomTwoArg", arg1: "Not enough args" };

const badCustomType_KindInvalid = { kind: "Invalid kind find" };
const badCustomType_KindMismatched: Custom = { kind: "FirstName" };
const badCustomType_KindMismatched_2: CustomOneArg = { kind: "CustomNoArg" };
