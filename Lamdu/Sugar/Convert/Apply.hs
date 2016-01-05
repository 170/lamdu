{-# LANGUAGE NoImplicitPrelude, NamedFieldPuns #-}
module Lamdu.Sugar.Convert.Apply
    ( convert
    ) where

import           Prelude.Compat

import qualified Control.Lens as Lens
import           Control.Lens.Operators
import           Control.Monad (MonadPlus(..), guard, unless)
import           Control.Monad.Trans.Class (lift)
import           Control.Monad.Trans.Either.Utils (runMatcherT, justToLeft)
import           Control.Monad.Trans.Maybe (MaybeT(..))
import           Control.Monad.Trans.State (evalStateT, runStateT)
import           Control.MonadA (MonadA)
import qualified Data.Foldable as Foldable
import qualified Data.Map as Map
import           Data.Maybe.Utils (maybeToMPlus)
import qualified Data.Set as Set
import           Data.Store.Guid (Guid)
import qualified Data.Store.Property as Property
import           Data.Store.Transaction (Transaction)
import qualified Lamdu.Builtins.Anchors as Builtins
import qualified Lamdu.Data.Ops as DataOps
import qualified Lamdu.Expr.IRef as ExprIRef
import qualified Lamdu.Expr.IRef.Infer as IRefInfer
import qualified Lamdu.Expr.Lens as ExprLens
import qualified Lamdu.Expr.Pure as P
import qualified Lamdu.Expr.RecordVal as RecordVal
import           Lamdu.Expr.Type (Type)
import qualified Lamdu.Expr.UniqueId as UniqueId
import           Lamdu.Expr.Val (Val(..))
import qualified Lamdu.Expr.Val as V
import qualified Lamdu.Infer as Infer
import           Lamdu.Infer.Unify (unify)
import           Lamdu.Sugar.Convert.Expression.Actions (addActions)
import qualified Lamdu.Sugar.Convert.Hole as ConvertHole
import qualified Lamdu.Sugar.Convert.Hole.Suggest as Suggest
import qualified Lamdu.Sugar.Convert.Input as Input
import           Lamdu.Sugar.Convert.Monad (ConvertM)
import qualified Lamdu.Sugar.Convert.Monad as ConvertM
import           Lamdu.Sugar.Internal
import qualified Lamdu.Sugar.Internal.EntityId as EntityId
import           Lamdu.Sugar.Types

type T = Transaction

convert ::
    (MonadA m, Monoid a) => V.Apply (Val (Input.Payload m a)) ->
    Input.Payload m a -> ConvertM m (ExpressionU m a)
convert app@(V.Apply funcI argI) exprPl =
    runMatcherT $
    do
        (funcS, argS) <-
            do
                argS <- lift $ ConvertM.convertSubexpression argI
                justToLeft $ convertAppliedHole app argS exprPl
                funcS <- ConvertM.convertSubexpression funcI & lift
                protectedSetToVal <- lift ConvertM.typeProtectedSetToVal
                let setToFuncAction =
                        maybe NoInnerExpr SetToInnerExpr $
                        do
                            outerStored <- exprPl ^. Input.stored
                            funcStored <- funcI ^. V.payload . Input.stored
                            protectedSetToVal outerStored
                                (Property.value funcStored)
                                <&> EntityId.ofValI & return
                if Lens.has (rBody . _BodyHole) argS
                    then
                    return
                    ( funcS
                      & rPayload . plActions . Lens._Just . setToHole .~
                        AlreadyAppliedToHole
                    , argS
                      & rPayload . plActions . Lens._Just . setToInnerExpr .~
                        setToFuncAction
                    )
                    else return (funcS, argS)
        justToLeft $
            convertAppliedCase (funcS ^. rBody) (funcI ^. V.payload) argS exprPl
        justToLeft $ convertLabeled funcS argS argI exprPl
        lift $ convertPrefix funcS argS exprPl

noRepetitions :: Ord a => [a] -> Bool
noRepetitions x = length x == Set.size (Set.fromList x)

convertLabeled ::
    (MonadA m, Monoid a) =>
    ExpressionU m a -> ExpressionU m a -> Val (Input.Payload m a) -> Input.Payload m a ->
    MaybeT (ConvertM m) (ExpressionU m a)
convertLabeled funcS argS argI exprPl =
    do
        guard $ Lens.has (rBody . _BodyGetVar . _GetBinder . bvForm . _GetDefinition) funcS
        record <- maybeToMPlus $ argS ^? rBody . _BodyRecord
        guard $ length (record ^. rItems) >= 2
        let getArg field =
                AnnotatedArg
                    { _aaTag = field ^. rfTag
                    , _aaExpr = field ^. rfExpr
                    }
        let args = map getArg $ record ^. rItems
        let tags = args ^.. Lens.traversed . aaTag . tagVal
        unless (noRepetitions tags) $ error "Repetitions should not type-check"
        protectedSetToVal <- lift ConvertM.typeProtectedSetToVal
        let setToInnerExprAction =
                maybe NoInnerExpr SetToInnerExpr $
                do
                    stored <- exprPl ^. Input.stored
                    val <-
                        case (filter (Lens.nullOf ExprLens.valHole) . map snd . Map.elems) fieldsI of
                        [x] -> Just x
                        _ -> Nothing
                    valStored <- traverse (^. Input.stored) val
                    return $
                        EntityId.ofValI <$>
                        protectedSetToVal stored (Property.value (valStored ^. V.payload))
        BodyApply Apply
            { _aFunc = funcS
            , _aSpecialArgs = NoSpecialArgs
            , _aAnnotatedArgs = args
            }
            & lift . addActions exprPl
            <&> rPayload %~
                ( plData <>~ (argS ^. rPayload . plData) ) .
                ( plActions . Lens._Just . setToInnerExpr .~ setToInnerExprAction
                )
    where
        (fieldsI, Val _ (V.BLeaf V.LRecEmpty)) = RecordVal.unpack argI

convertPrefix ::
    (MonadA m, Monoid a) =>
    ExpressionU m a -> ExpressionU m a ->
    Input.Payload m a -> ConvertM m (ExpressionU m a)
convertPrefix funcS argS applyPl =
    addActions applyPl $ BodyApply Apply
    { _aFunc = funcS
    , _aSpecialArgs = ObjectArg argS
    , _aAnnotatedArgs = []
    }

orderedInnerHoles :: Val a -> [Val a]
orderedInnerHoles e =
    case e ^. V.body of
    V.BLeaf V.LHole -> [e]
    V.BApp (V.Apply func@(V.Val _ (V.BLeaf V.LHole)) arg) ->
        orderedInnerHoles arg ++ [func]
    body -> Foldable.concatMap orderedInnerHoles body

unwrap ::
    MonadA m =>
    ExprIRef.ValIProperty m ->
    ExprIRef.ValIProperty m ->
    Val (Input.Payload n a) ->
    T m EntityId
unwrap outerP argP argExpr =
    do
        res <- DataOps.replace outerP (Property.value argP)
        return $
            case orderedInnerHoles argExpr of
            (x:_) -> x ^. V.payload . Input.entityId
            _ -> EntityId.ofValI res

checkTypeMatch :: MonadA m => Type -> Type -> ConvertM m Bool
checkTypeMatch x y =
    do
        inferContext <- (^. ConvertM.scInferContext) <$> ConvertM.readContext
        return $ Lens.has Lens._Right $ evalStateT (Infer.run (unify x y)) inferContext

mkAppliedHoleOptions ::
    MonadA m =>
    ConvertM.Context m ->
    Val (Input.Payload m a) ->
    Expression name m a ->
    Input.Payload m a ->
    ExprIRef.ValIProperty m ->
    [HoleOption Guid m]
mkAppliedHoleOptions sugarContext argI argS exprPl stored =
    [ P.app P.hole P.hole | Lens.nullOf (rBody . _BodyLam) argS ] ++
    [ P.record
      [ (Builtins.headTag, P.hole)
      , ( Builtins.tailTag
        , P.inject Builtins.nilTag P.recEmpty & P.toNom Builtins.listTid
        )
      ]
      & P.inject Builtins.consTag
      & P.toNom Builtins.listTid
    ]
    <&> ConvertHole.SeedExpr
    <&> ConvertHole.mkHoleOption sugarContext (Just argI) exprPl stored

mkAppliedHoleSuggesteds ::
    MonadA m =>
    ConvertM.Context m ->
    Val (Input.Payload m a) ->
    Input.Payload m a ->
    ExprIRef.ValIProperty m ->
    T m [HoleOption Guid m]
mkAppliedHoleSuggesteds sugarContext argI exprPl stored =
    Suggest.valueConversion IRefInfer.loadNominal Nothing (argI <&> onPl)
    <&> (`runStateT` (sugarContext ^. ConvertM.scInferContext))
    <&> Lens.mapped %~ onSuggestion
    where
        onPl pl = (pl ^. Input.inferred, Just pl)
        onSuggestion (sugg, newInferCtx) =
            ConvertHole.mkHoleOptionFromInjected
            (sugarContext & ConvertM.scInferContext .~ newInferCtx)
            exprPl stored
            (sugg <&> Lens._1 %~ (^. Infer.plType))

convertAppliedHole ::
    (MonadA m, Monoid a) =>
    V.Apply (Val (Input.Payload m a)) -> ExpressionU m a ->
    Input.Payload m a ->
    MaybeT (ConvertM m) (ExpressionU m a)
convertAppliedHole (V.Apply funcI argI) argS exprPl =
    do
        guard $ Lens.has ExprLens.valHole funcI
        isTypeMatch <-
            checkTypeMatch (argI ^. V.payload . Input.inferredType)
            (exprPl ^. Input.inferredType) & lift
        let mUnwrap =
                do
                    stored <- mStored
                    argP <- argI ^. V.payload . Input.stored
                    return $ unwrap stored argP argI
        let holeArg = HoleArg
                { _haExpr =
                      argS
                      & rPayload . plActions . Lens._Just . wrap .~
                        maybe WrapNotAllowed WrappedAlready mStoredEntityId
                      & rPayload . plActions . Lens._Just . setToHole .~
                        ( mStored <&> fmap guidEntityId . DataOps.setToHole
                        & maybe AlreadyAHole SetWrapperToHole )
                , _haUnwrap =
                      if isTypeMatch
                      then UnwrapMAction mUnwrap
                      else UnwrapTypeMismatch
                }
        do
            sugarContext <- ConvertM.readContext
            hole <- ConvertHole.convertCommon (Just argI) exprPl
            case mStored of
                Nothing -> return hole
                Just stored ->
                    do
                        suggesteds <-
                            mkAppliedHoleSuggesteds sugarContext
                            argI exprPl stored
                            & ConvertM.liftTransaction
                        hole
                            & rBody . _BodyHole . holeMActions
                            . Lens._Just . holeOptions . Lens.mapped
                                %~  ConvertHole.addSuggestedOptions suggesteds
                                .   mappend (mkAppliedHoleOptions sugarContext
                                    argI argS exprPl stored)
                            & return
            & lift
            <&> rBody . _BodyHole . holeMArg .~ Just holeArg
            <&> rPayload . plData <>~ funcI ^. V.payload . Input.userData
            <&> rPayload . plActions . Lens._Just . wrap .~
                maybe WrapNotAllowed WrapperAlready mStoredEntityId
    where
        mStoredEntityId = mStored <&> addEntityId
        mStored = exprPl ^. Input.stored
        addEntityId = guidEntityId . Property.value
        guidEntityId valI = (UniqueId.toGuid valI, EntityId.ofValI valI)

convertAppliedCase ::
    (MonadA m, Monoid a) =>
    Body Guid m (ExpressionU m a) -> Input.Payload m a ->
    ExpressionU m a -> Input.Payload m a ->
    MaybeT (ConvertM m) (ExpressionU m a)
convertAppliedCase (BodyCase caseB) casePl argS exprPl =
    do
        Lens.has (cKind . _LambdaCase) caseB & guard
        protectedSetToVal <- lift ConvertM.typeProtectedSetToVal
        caseB
            & cKind .~ CaseWithArg
                CaseArg
                { _caVal = argS
                , _caMToLambdaCase =
                    protectedSetToVal
                    <$> exprPl ^. Input.stored
                    <*> (casePl ^. Input.stored <&> Property.value)
                    <&> Lens.mapped %~ EntityId.ofValI
                }
            & BodyCase
            & lift . addActions exprPl
    <&> rPayload . plData <>~ casePl ^. Input.userData
convertAppliedCase _ _ _ _ = mzero
