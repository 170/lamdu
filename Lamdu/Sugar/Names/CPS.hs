{-# LANGUAGE DeriveFunctor, RankNTypes, CPP #-}
module Lamdu.Sugar.Names.CPS
    ( CPS(..)
    ) where

#if __GLASGOW_HASKELL__ < 710
import Control.Applicative (Applicative(..))
#endif

data CPS m a = CPS { runCPS :: forall r. m r -> m (a, r) }
    deriving (Functor)

instance Functor m => Applicative (CPS m) where
    pure x = CPS $ fmap ((,) x)
    CPS cpsf <*> CPS cpsx =
        CPS (fmap foo . cpsf . cpsx)
        where
            foo (f, (x, r)) = (f x, r)
