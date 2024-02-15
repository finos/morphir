---
id: morphir-scala-support
title: Morphir Scala Support
---

This page details which Morphir-Elm features are currently supported.

## SDK Compatibility
This section lists the SDK types and functions currently supported in this version of Morphir-Scala.

### Morphir.SDK.Aggregate
| Function                 | Morphir-Elm Version Introduced | Supported |
|--------------------------|--------------------------------|-----------|
| groupBy                  | v2.65.1                        | &#x2715;  |
| aggregate                | v2.65.1                        | &#x2715;  |
| aggregateMap             | v2.19.0                        | &#x2715;  |
| aggregateMap2            | v2.19.0                        | &#x2715;  |
| aggregateMap3            | v2.19.0                        | &#x2715;  |
| aggregateMap4            | v2.68.0                        | &#x2715;  |
| count                    | v2.19.0                        | &#x2715;  |
| sumOf                    | v2.19.0                        | &#x2715;  |
| minimumOf                | v2.19.0                        | &#x2715;  |
| maximumOf                | v2.19.0                        | &#x2715;  |
| averageOf                | v2.19.0                        | &#x2715;  |
| weightedAverageOf        | v2.19.0                        | &#x2715;  |
| byKey                    | v2.19.0                        | &#x2715;  |
| withFilter               | v2.19.0                        | &#x2715;  |
| constructAggregationCall | v2.66.0                        | &#x2715;  |

### Morphir.SDK.Basics

#### Bool
| Function | Morphir-Elm Version Introduced | Supported |
|----------|--------------------------------|-----------|
| not      | v0.4.0                         | &#x2713;  |
| and      | v0.4.0                         | &#x2713;  |
| or       | v0.4.0                         | &#x2713;  |
| xor      | v0.4.0                         | &#x2713;  |

#### Char
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| lessThan           | v2.0.0                         | &#x2713;  |
| greaterThan        | v2.0.0                         | &#x2715;  |
| lessThanOrEqual    | v2.0.0                         | &#x2715;  |
| greaterThanOrEqual | v2.0.0                         | &#x2715;  |
| max                | v2.0.0                         | &#x2715;  |
| min                | v2.0.0                         | &#x2715;  |
| compare            | v2.0.0                         | &#x2713;  |

#### Float
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
| divide             | v0.4.0                         | &#x2713;  |
| round              | v0.4.0                         | &#x2715;  |
| floor              | v0.4.0                         | &#x2715;  |
| ceiling            | v0.4.0                         | &#x2715;  |
| truncate           | v0.4.0                         | &#x2715;  |
| isNan              | v0.4.0                         | &#x2715;  |
| isInfinite         | v0.4.0                         | &#x2715;  |
| e                  | v0.4.0                         | &#x2713;  |
| pi                 | v0.4.0                         | &#x2713;  |
| cos                | v0.4.0                         | &#x2715;  |
| sin                | v0.4.0                         | &#x2715;  |
| tan                | v0.4.0                         | &#x2715;  |
| acos               | v0.4.0                         | &#x2715;  |
| asin               | v0.4.0                         | &#x2715;  |
| atan               | v0.4.0                         | &#x2715;  |
| atan2              | v0.4.0                         | &#x2715;  |
| degrees            | v2.0.0                         | &#x2715;  | 
| radians            | v2.0.0                         | &#x2715;  | 
| turns              | v2.0.0                         | &#x2715;  | 
| toPolar            | v2.0.0                         | &#x2715;  | 
| fromPolar          | v2.0.0                         | &#x2715;  | 
| lessThan           | v2.0.0                         | &#x2713;  |
| greaterThan        | v2.0.0                         | &#x2715;  |
| lessThanOrEqual    | v2.0.0                         | &#x2715;  |
| greaterThanOrEqual | v2.0.0                         | &#x2715;  |
| max                | v2.0.0                         | &#x2715;  |
| min                | v2.0.0                         | &#x2715;  |
| compare            | v2.0.0                         | &#x2713;  |

#### Int
| Function           | Morphir-Elm Version Introduced | Supported |
|--------------------|--------------------------------|-----------|
