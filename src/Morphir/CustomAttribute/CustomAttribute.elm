module Morphir.CustomAttribute.CustomAttribute exposing (..)
import Morphir.Compiler exposing (FilePath)
import Morphir.IR.Type exposing (Type)


type alias AttributeName 
	= String

type alias CustomAttributeConfig =
	{ attributeName : AttributeName
	, filePath : FilePath
	, type : Type ()
	}