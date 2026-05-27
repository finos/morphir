/**
 * Re-export IR types for browser consumption.
 *
 * The web bundle shares these types with the CLI/server side.  The `../src/ir`
 * directory is included in `tsconfig.app.json` so Vite can resolve these
 * imports at build time.
 */
export type {
    Access,
    AccessControlled,
    Constructors,
    Distribution,
    Documented,
    Field,
    FQName,
    Literal,
    ModuleDefinition,
    ModuleSpecification,
    Name,
    PackageDefinition,
    PackageSpecification,
    Path,
    Pattern,
    Type,
    TypeDefinition,
    TypeSpecification,
    Value,
    ValueDefinition,
    ValueSpecification,
} from "../../../src/ir/distribution";

export type { TypeAttrs, ValueAttrs, SubstrateDistribution } from "../../../src/ir/attrs";

export type { NodePath, LocationKey, SourceLocationIndex } from "../../../src/ir/source-location";

export {
    buildDistribution as buildSimplifiedDistribution,
    decodeModule as decodeSimplifiedModule,
    decodeType as decodeSimplifiedType,
    decodeValue as decodeSimplifiedValue,
    decodePattern as decodeSimplifiedPattern,
    decodeValueDefinition as decodeSimplifiedValueDefinition,
    fqnFromString,
    inferPackageName,
    modulePathFromRelPath,
    nameFromCased,
    pathFromDotted,
    tryBuildDistribution as tryBuildSimplifiedDistribution,
    SimplifiedDecodeError,
} from "../../../src/ir/simplified";
export type {
    SimplifiedModuleFile,
    SimplifiedDecodeResult,
} from "../../../src/ir/simplified";
