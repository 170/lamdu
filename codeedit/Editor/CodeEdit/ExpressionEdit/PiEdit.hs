{-# LANGUAGE OverloadedStrings #-}
module Editor.CodeEdit.ExpressionEdit.PiEdit(make) where

import Editor.Anchors (ViewTag)
import Editor.OTransaction (OTransaction)
import Editor.MonadF (MonadF)
import Editor.CodeEdit.ExpressionEdit.ExpressionGui (ExpressionGui)
import qualified Editor.BottleWidgets as BWidgets
import qualified Editor.OTransaction as OT
import qualified Editor.CodeEdit.ExpressionEdit.ExpressionGui as ExpressionGui
import qualified Editor.CodeEdit.ExpressionEdit.FuncEdit as FuncEdit
import qualified Editor.CodeEdit.Sugar as Sugar
import qualified Editor.Config as Config
import qualified Editor.Data as Data
import qualified Editor.WidgetIds as WidgetIds
import qualified Graphics.UI.Bottle.Widget as Widget

make
  :: MonadF m
  => ExpressionGui.Maker m
  -> Sugar.Pi m
  -> Widget.Id
  -> OTransaction ViewTag m (ExpressionGui m)
make makeExpressionEdit (Sugar.Pi param resultType) myId =
  OT.assignCursor myId typeId $ do
    (resultTypeEdit, usedVars) <-
      OT.usedVariables $ FuncEdit.makeBodyEdit makeExpressionEdit
      [WidgetIds.paramId . Sugar.guid $ Sugar.fpEntity param] resultType
    let
      paramGuid = Sugar.guid $ Sugar.fpEntity param
      paramUsed = any ((== paramGuid) . Data.variableRefGuid) usedVars
      redirectCursor cursor
        | paramUsed = cursor
        | otherwise =
          case Widget.subId (WidgetIds.paramId paramGuid) cursor of
          Nothing -> cursor
          Just _ -> typeId
    OT.atCursor redirectCursor $ do
      paramEdit <-
        if paramUsed
        then FuncEdit.makeParamEdit makeExpressionEdit ("Result Type", resultType) param
        else makeExpressionEdit $ Sugar.fpType param
      rightArrowLabel <-
        OT.setTextSizeColor Config.rightArrowTextSize Config.rightArrowColor .
        BWidgets.makeLabel "→" $ Widget.toAnimId myId
      return $
        ExpressionGui.hboxSpaced [paramEdit, ExpressionGui.fromValueWidget rightArrowLabel, resultTypeEdit]
  where
    typeId =
      WidgetIds.fromGuid . Sugar.guid . Sugar.rEntity . Sugar.fpType $
      param
