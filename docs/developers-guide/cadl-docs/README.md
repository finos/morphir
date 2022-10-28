# Morphir Type Mappings To CADL
## SDK Types to CADL
####### NB: CADL has a numeric type which consist of two subtypes called integer and float

#### Basic Types
###### Bool
    This maps to the `boolean` type in CADL. 
    Example: 
        alias InCadl = boolean
###### Int
    In CADL, this maps to the subtype `integer`, which further has theses subtypes ::  
    [-] int8        [-] uint8       [-] safeint
    [-] int16       [-] uint16
    [-] int32       [-] unit32
    [-] int64       [-] unit32
    
    NB - To assign an `integer` type, you need to actually assign a subtype instead else the `integer` type defaults to an object. 

    Example: 
        alias length = int32 
###### Float
    In CADL, this maps to the subtype `float`, which further has theses subtypes :  
    [-] float32   
    [-] float64

    NB:: To assign an `float` type, you need to actually assign a subtype instead else the `float` type defaults to an object.
    
    Example: 
        alias PI = float32
###### String
    This maps to the same type `string` in CADL.
    
    Example: 
        alias KG = "KiloGram"
###### Char
    In CADL, the concept of a `char` type doesn't exist. An alternative would be to use the `string` type. 

#### Advanced Types
###### Decimal
    This is Not supported directly in CADL. An alternative would be to use string. 

###### LocalDate
    Morphir type `localDate` maps to `plainDate` type in CADL. 
    
    Example: 
        alias dateOfBirth = plainDate
###### LocalTime
    Morphir type `localTime`  maps to `plainTime` type in CADL. 
    
    Example: 
        alias loginTime = plainTime
###### Month
    In CADL, the concept of `month` type exists not. An alterative would be to use the `string` type

###### Optional Values(Maybe) 
    In CADL, morphir type `maybe` is not directly supported but could be achieved through various approach.  
    1. As an optional field of a record `type` using the `?:` syntax. 
        Example :
            model Person {
                address ?: string
            }
    2. Defined as `union` type with null as another value
        alias mayBe = Person | null

#### Collections Types
###### List
        List in morphir, maps to the`array` type in CADL. In CADL, arrays are created using the `[]` or Array<model> syntax.
        Example : 
            model PhoneNumber {
                code: string,
                number: string
            }

            model Person {
                contactNumbers: PhoneNumber[] // OR Array<PhoneNumber>
            }
###### Set
        This is not supported directly in CADL. An alternative would be to use `array` type. 

###### Dict
        The Dict type in morphir is not directly supported in CADL but could be defined it as an alias with values of list of tuples.
        Example: 
            alias Dict<K,V> = Array<[K,V]> ;

##### Result 
        The concept of morphir type `result` is not supported directly in CADL, but could be defined as an alias type whose values are `union` types. 
        alias Result<OK | ERR> = OK | ERR
        
        Example : 
            model Ok<T> {status: int8, data: T} 
            model ERR<T> {code: int8, message: T}
            alias Result<OK,ERR> = OK | ERR ;

### Composite Types
#### Tuples
    Tuples being a subtype of `array` in CADL, are respresented as more than One argument type of the `array` type.
    Example : 
        model TouristSite {...}
        model Country {...}
        
        model Person {
            visits: [Country, Array<TouristSite>]
        }
###### Record Types
    Morphir `record` type maps to whats called `model` in CADL. Models are structures with fields called properties and are used to used to represent data shapes 
    or schemas.
    
    Example:
        model Person {
            name: string,
            dob: plainDate,
            addr ?: string, // optional field
            gender: "male" | "female" // union type
        }
#### Custom Types
###### General
    ???
###### Special Cases
    ???