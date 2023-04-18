
class DecodeError extends Error { }

Object.defineProperty(DecodeError.prototype, "name", {
  value: "DecodeError",
});

export namespace Morphir_SDK_Decimal{
    type Decimal =  number;

    export function decodeDecimal(input: any): Decimal {
        if (typeof input != "number") {
          throw new DecodeError(`Expected Decimal, got ${typeof input}`);
        }
        return input;
    }

    export function encodeDecimal(value: Decimal): Decimal {
        return value;
    }
}
  