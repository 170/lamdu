{-# OPTIONS -fno-warn-orphans #-}
{-# LANGUAGE StandaloneDeriving, DeriveGeneric #-}
module Lamdu.Config (Layers(..), Config(..), delKeys) where

import Data.Aeson (ToJSON(..), FromJSON(..))
import Data.Vector.Vector2 (Vector2(..))
import Foreign.C.Types (CDouble)
import GHC.Generics (Generic)
import Graphics.DrawingCombinators.Utils () -- Read instance for Color
import qualified Graphics.DrawingCombinators as Draw
import qualified Graphics.UI.Bottle.EventMap as E

data Layers = Layers
  { layerCursorBG
  , layerTypes
  , layerChoiceBG
  , layerHoleBG
  , layerNameCollisionBG
  , layerLabeledApplyBG
  , layerParensHighlightBG
  , layerActivePane
  , layerMax :: Int
  } deriving (Eq, Generic)

data Config = Config
  { layers :: Layers
  , baseColor :: Draw.Color
  , baseTextSize :: Int
  , helpTextColor :: Draw.Color
  , helpTextSize :: Int
  , helpInputDocColor :: Draw.Color
  , helpBGColor :: Draw.Color

  , invalidCursorBGColor :: Draw.Color

  , quitKeys :: [E.ModKey]
  , undoKeys :: [E.ModKey]
  , redoKeys :: [E.ModKey]
  , makeBranchKeys :: [E.ModKey]

  , jumpToBranchesKeys :: [E.ModKey]

  , overlayDocKeys :: [E.ModKey]

  , addNextParamKeys :: [E.ModKey]

  , delBranchKeys :: [E.ModKey]

  , closePaneKeys :: [E.ModKey]
  , movePaneDownKeys :: [E.ModKey]
  , movePaneUpKeys :: [E.ModKey]

  , replaceKeys :: [E.ModKey]

  , pickResultKeys :: [E.ModKey]
  , pickAndMoveToNextHoleKeys :: [E.ModKey]

  , jumpToNextHoleKeys :: [E.ModKey]
  , jumpToPrevHoleKeys :: [E.ModKey]

  , jumpToDefinitionKeys :: [E.ModKey]

  , delForwardKeys :: [E.ModKey]
  , delBackwardKeys :: [E.ModKey]
  , wrapKeys :: [E.ModKey]
  , debugModeKeys :: [E.ModKey]

  , newDefinitionKeys :: [E.ModKey]

  , definitionColor :: Draw.Color
  , parameterColor :: Draw.Color
  , paramOriginColor :: Draw.Color

  , literalIntColor :: Draw.Color

  , previousCursorKeys :: [E.ModKey]

  , holeResultCount :: Int
  , holeResultScaleFactor :: Vector2 Double
  , holeResultPadding :: Vector2 Double
  , holeResultInjectedScaleExponent :: Double
  , holeSearchTermScaleFactor :: Vector2 Double
  , holeNumLabelScaleFactor :: Vector2 Double
  , holeNumLabelColor :: Draw.Color
  , holeInactiveExtraSymbolColor :: Draw.Color

  , typeErrorHoleWrapBackgroundColor :: Draw.Color
  , deletableHoleBackgroundColor :: Draw.Color

  , activeHoleBackgroundColor :: Draw.Color
  , inactiveHoleBackgroundColor :: Draw.Color

  , wrapperHolePadding :: Vector2 Double

  , tagScaleFactor :: Vector2 Double

  , fieldTagScaleFactor :: Vector2 Double
  , fieldTint :: Draw.Color

  , suggestedValueScaleFactor :: Vector2 Double
  , suggestedValueTint :: Draw.Color

  , parenHighlightColor :: Draw.Color

  , addWhereItemKeys :: [E.ModKey]

  , lambdaColor :: Draw.Color
  , lambdaTextSize :: Int

  , rightArrowColor :: Draw.Color
  , rightArrowTextSize :: Int

  , whereColor :: Draw.Color
  , whereScaleFactor :: Vector2 Double
  , whereLabelScaleFactor :: Vector2 Double

  , typeScaleFactor :: Vector2 Double
  , squareParensScaleFactor :: Vector2 Double

  , foreignModuleColor :: Draw.Color
  , foreignVarColor :: Draw.Color

  , cutKeys :: [E.ModKey]
  , pasteKeys :: [E.ModKey]

  , inactiveTintColor :: Draw.Color
  , activeDefBGColor :: Draw.Color

  , inferredTypeTint :: Draw.Color
  , inferredTypeErrorBGColor :: Draw.Color
  , inferredTypeBGColor :: Draw.Color

-- For definitions
  , defOriginForegroundColor :: Draw.Color

  , builtinOriginNameColor :: Draw.Color

  , cursorBGColor :: Draw.Color

  , listBracketTextSize :: Int
  , listBracketColor :: Draw.Color
  , listCommaTextSize :: Int
  , listCommaColor :: Draw.Color

  , listAddItemKeys :: [E.ModKey]

  , selectedBranchColor :: Draw.Color

  , jumpLHStoRHSKeys :: [E.ModKey]
  , jumpRHStoLHSKeys :: [E.ModKey]

  , shrinkBaseFontKeys :: [E.ModKey]
  , enlargeBaseFontKeys :: [E.ModKey]

  , enlargeFactor :: Double
  , shrinkFactor :: Double

  , defTypeLabelTextSize :: Int
  , defTypeLabelColor :: Draw.Color

  , defTypeBoxScaleFactor :: Vector2 Double

  , acceptKeys :: [E.ModKey]

  , autoGeneratedNameTint :: Draw.Color
  , collisionSuffixTextColor :: Draw.Color
  , collisionSuffixBGColor :: Draw.Color
  , collisionSuffixScaleFactor :: Vector2 Double

  , paramDefSuffixScaleFactor :: Vector2 Double

  , enterSubexpressionKeys :: [E.ModKey]
  , leaveSubexpressionKeys :: [E.ModKey]

  , nextInfoModeKeys :: [E.ModKey]

  , recordTailColor :: Draw.Color
  , recordAddFieldKeys :: [E.ModKey]

  , presentationChoiceScaleFactor :: Vector2 Double
  , presentationChoiceColor :: Draw.Color

  , labeledApplyBGColor :: Draw.Color
  , labeledApplyPadding :: Vector2 Double
  , spaceBetweenAnnotatedArgs :: Double
  } deriving (Eq, Generic)

delKeys :: Config -> [E.ModKey]
delKeys config = delForwardKeys config ++ delBackwardKeys config

instance ToJSON a => ToJSON (Vector2 a)
instance FromJSON a => FromJSON (Vector2 a)

deriving instance Generic Draw.Color

instance ToJSON Draw.Color
instance FromJSON Draw.Color

instance ToJSON E.ModState
instance FromJSON E.ModState

instance ToJSON E.ModKey
instance FromJSON E.ModKey

instance ToJSON E.Key
instance FromJSON E.Key

instance ToJSON Layers
instance FromJSON Layers

instance ToJSON Config
instance FromJSON Config

instance FromJSON CDouble where
  parseJSON = fmap (realToFrac :: Double -> CDouble) . parseJSON
instance ToJSON CDouble where
  toJSON = toJSON . (realToFrac :: CDouble -> Double)
