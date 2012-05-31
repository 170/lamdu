{-# LANGUAGE TemplateHaskell, Rank2Types, StandaloneDeriving, FlexibleInstances, FlexibleContexts, UndecidableInstances #-}
module Editor.Data
  ( Definition(..), atDefBody, atDefType
  , FFIName(..)
  , VariableRef(..), variableRefGuid
  , Lambda(..), atLambdaParamType, atLambdaBody
  , Apply(..), atApplyFunc, atApplyArg
  , Expression(..)
  )
where

import Control.Applicative (pure, liftA2)
import Data.Binary (Binary(..))
import Data.Binary.Get (getWord8)
import Data.Binary.Put (putWord8)
import Data.Derive.Binary(makeBinary)
import Data.DeriveTH(derive)
import Data.Store.Guid (Guid)
import Data.Store.IRef(IRef)
import qualified Data.AtFieldTH as AtFieldTH
import qualified Data.Store.IRef as IRef

data Lambda i = Lambda {
  lambdaParamType :: i (Expression i),
  lambdaBody :: i (Expression i)
  }

data Apply i = Apply {
  applyFunc :: i (Expression i),
  applyArg :: i (Expression i)
  }

data VariableRef
  = ParameterRef Guid -- of the lambda/pi
  | DefinitionRef (IRef (Definition IRef))

data Expression i
  = ExpressionLambda (Lambda i)
  | ExpressionPi (Lambda i)
  | ExpressionApply (Apply i)
  | ExpressionGetVariable VariableRef
  | ExpressionHole
  | ExpressionLiteralInteger Integer
  | ExpressionBuiltin FFIName
  | ExpressionMagic

data FFIName = FFIName
  { fModule :: [String]
  , fName :: String
  } deriving (Eq, Ord, Read, Show)

data Definition i = Definition
  { defType :: i (Expression i)
  , defBody :: i (Expression i)
  }

instance Binary (i (Expression i)) => Binary (Definition i) where
  get = liftA2 Definition get get
  put (Definition x y) = put x >> put y

instance Binary VariableRef where
  get = do
    tag <- getWord8
    case tag of
      0 -> fmap ParameterRef  get
      1 -> fmap DefinitionRef get
      _ -> fail "Invalid tag in serialization of VariableRef"
  put (ParameterRef x)  = putWord8 0 >> put x
  put (DefinitionRef x) = putWord8 1 >> put x

instance Eq VariableRef where
  ParameterRef x == ParameterRef y = x == y
  DefinitionRef x == DefinitionRef y = x == y
  _ == _ = False

instance Binary (i (Expression i)) => Binary (Expression i) where
  get = do
    tag <- getWord8
    case tag of
      0 -> fmap ExpressionLambda $ liftA2 Lambda get get
      1 -> fmap ExpressionPi     $ liftA2 Lambda get get
      2 -> fmap ExpressionApply  $ liftA2 Apply get get
      3 -> fmap ExpressionGetVariable get
      4 -> pure ExpressionHole
      5 -> fmap ExpressionLiteralInteger get
      6 -> fmap ExpressionBuiltin get
      7 -> pure ExpressionMagic
      _ -> fail "Invalid tag in serialization of Expression"
  put (ExpressionLambda (Lambda x y)) = putWord8 0 >> put x >> put y
  put (ExpressionPi (Lambda x y))     = putWord8 1 >> put x >> put y
  put (ExpressionApply (Apply x y))   = putWord8 2 >> put x >> put y
  put (ExpressionGetVariable x)       = putWord8 3 >> put x
  put ExpressionHole                  = putWord8 4
  put (ExpressionLiteralInteger x)    = putWord8 5 >> put x
  put (ExpressionBuiltin x)           = putWord8 6 >> put x
  put ExpressionMagic                 = putWord8 7

instance Eq (i (Expression i)) => Eq (Expression i) where
  ExpressionLambda (Lambda x0 y0) == ExpressionLambda (Lambda x1 y1) =
    x0 == x1 && y0 == y1
  ExpressionPi (Lambda x0 y0) == ExpressionPi (Lambda x1 y1) =
    x0 == x1 && y0 == y1
  ExpressionApply (Apply x0 y0) == ExpressionApply (Apply x1 y1) =
    x0 == x1 && y0 == y1
  ExpressionGetVariable x == ExpressionGetVariable y = x == y
  ExpressionHole == ExpressionHole = True
  ExpressionLiteralInteger x == ExpressionLiteralInteger y = x == y
  ExpressionBuiltin x == ExpressionBuiltin y = x == y
  ExpressionMagic == ExpressionMagic = True
  _ == _ = False

variableRefGuid :: VariableRef -> Guid
variableRefGuid (ParameterRef i) = i
variableRefGuid (DefinitionRef i) = IRef.guid i

derive makeBinary ''FFIName
AtFieldTH.make ''Lambda
AtFieldTH.make ''Apply
AtFieldTH.make ''Definition
