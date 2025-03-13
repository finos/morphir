package org.finos.morphir.mdl.ast

public sealed interface MorphirValue
public sealed interface MorphirBuiltinValue : MorphirValue {}
public sealed interface MorphirScalarValue : MorphirValue {}
public sealed interface MorphirBuiltinScalarValue: MorphirBuiltinValue, MorphirScalarValue

public data object MorphirNull : MorphirBuiltinValue
public data class MorphirBoolean(val value: Boolean) : MorphirBuiltinScalarValue

public data class MorphirNumber(val value: Number) : MorphirBuiltinScalarValue
public data class MorphirString(val value: String) : MorphirBuiltinScalarValue

public data class MorphirStruct(val fields:List<Field>) : MorphirValue

//public data class MorphirOptional(val value: MorphirValue) : MorphirBuiltinValue
public data class MorphirList(val elements:List<MorphirValue>) : MorphirBuiltinValue

public data class Field(val name:String, val value: MorphirValue)
