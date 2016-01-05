module Lamdu.Sugar.PresentationModes
    ( addToDef, addToExpr
    ) where

import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.Lens.Tuple
import           Control.MonadA (MonadA)
import           Data.Store.Guid (Guid)
import           Data.Store.Transaction (Transaction)
import qualified Data.Store.Transaction as Transaction
import qualified Lamdu.Data.Anchors as Anchors
import           Lamdu.Sugar.Internal
import qualified Lamdu.Sugar.Types as Sugar

type T = Transaction

indirectDefinitionGuid :: ExpressionU m pl -> Maybe Guid
indirectDefinitionGuid funcS =
    case funcS ^. Sugar.rBody of
    Sugar.BodyGetVar
        (Sugar.GetBinder
         binderVar@Sugar.BinderVar { Sugar._bvForm = Sugar.GetDefinition }) ->
            Just $ binderVar ^. Sugar.bvNameRef . Sugar.nrName
    _ -> Nothing

indirectDefinitionPresentationMode ::
    MonadA m => ExpressionU m pl -> T m (Maybe Sugar.PresentationMode)
indirectDefinitionPresentationMode =
    Lens.traverse (Transaction.getP . Anchors.assocPresentationMode) .
    indirectDefinitionGuid

addToApply ::
    MonadA m =>
    Sugar.Apply name (ExpressionU m pl) ->
    T m (Sugar.Apply name (ExpressionU m pl))
addToApply a =
    case a ^. Sugar.aSpecialArgs of
    Sugar.NoSpecialArgs ->
        do
            presentationMode <-
                a ^. Sugar.aFunc & indirectDefinitionPresentationMode
            let (specialArgs, annotatedArgs) =
                    case (presentationMode, a ^. Sugar.aAnnotatedArgs) of
                    (Just (Sugar.Infix prec), a0:a1:as) ->
                        ( Sugar.InfixArgs prec
                          (a0 ^. Sugar.aaExpr) (a1 ^. Sugar.aaExpr)
                        , as
                        )
                    (Just Sugar.OO, a0:as) ->
                        (Sugar.ObjectArg (a0 ^. Sugar.aaExpr), as)
                    (_, args) -> (Sugar.NoSpecialArgs, args)
            a
                & Sugar.aAnnotatedArgs .~ annotatedArgs
                & Sugar.aSpecialArgs .~ specialArgs
                & return
    _ -> return a

addToHoleResult ::
    MonadA m => Sugar.HoleResult Guid m -> T m (Sugar.HoleResult Guid m)
addToHoleResult = Sugar.holeResultConverted %%~ addToExpr

addToHole :: MonadA m => Sugar.Hole Guid m a -> Sugar.Hole Guid m a
addToHole =
    Sugar.holeActions . Sugar.holeOptions .
    Lens.mapped . Lens.mapped . Sugar.hoResults . Lens.mapped .
    _2 %~ (>>= addToHoleResult)

addToBody :: MonadA m => BodyU m pl -> T m (BodyU m pl)
addToBody (Sugar.BodyApply a) = addToApply a <&> Sugar.BodyApply
addToBody (Sugar.BodyHole a) = addToHole a & Sugar.BodyHole & return
addToBody b = return b

addToExpr :: MonadA m => ExpressionU m pl -> T m (ExpressionU m pl)
addToExpr e =
    e
    & Sugar.rBody %%~ addToBody
    >>= Sugar.rBody . Lens.traversed %%~ addToExpr

addToBinder ::
    MonadA m =>
    Sugar.Binder Guid m (ExpressionU m pl) ->
    T m (Sugar.Binder Guid m (ExpressionU m pl))
addToBinder = Sugar.bBody %%~ addToBinderBody

addToBinderBody ::
    MonadA m =>
    Sugar.BinderBody Guid m (ExpressionU m pl) ->
    T m (Sugar.BinderBody Guid m (ExpressionU m pl))
addToBinderBody = Sugar.bbContent %%~ addToBinderContent

addToBinderContent ::
    MonadA m =>
    Sugar.BinderContent Guid m (ExpressionU m pl) ->
    T m (Sugar.BinderContent Guid m (ExpressionU m pl))
addToBinderContent (Sugar.BinderExpr e) = addToExpr e <&> Sugar.BinderExpr
addToBinderContent (Sugar.BinderLet l) = addToLet l <&> Sugar.BinderLet

addToLet ::
    MonadA m =>
    Sugar.Let Guid m (ExpressionU m pl) ->
    T m (Sugar.Let Guid m (ExpressionU m pl))
addToLet letItem =
    letItem
    & Sugar.lValue %%~ addToBinder
    >>= Sugar.lBody %%~ addToBinderBody

addToDef ::
    MonadA m =>
    Sugar.Definition Guid m (ExpressionU m a) ->
    T m (Sugar.Definition Guid m (ExpressionU m a))
addToDef def =
    def
    & Sugar.drBody . Sugar._DefinitionBodyExpression .
      Sugar.deContent %%~ addToBinder
