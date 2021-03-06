{-# language FlexibleContexts #-}

module Rel8.Query.These
  ( alignBy
  , keepHereTable, loseHereTable
  , keepThereTable, loseThereTable
  , keepThisTable, loseThisTable
  , keepThatTable, loseThatTable
  , keepThoseTable, loseThoseTable
  , bitraverseTheseTable
  )
where

-- base
import Prelude

-- opaleye
import qualified Opaleye.Internal.Join as Opaleye
import qualified Opaleye.Internal.PrimQuery as Opaleye

-- rel8
import Rel8.Expr ( Expr )
import Rel8.Expr.Bool ( boolExpr, not_ )
import Rel8.Expr.Eq ( (==.) )
import Rel8.Expr.Opaleye ( toColumn, toPrimExpr )
import Rel8.Expr.Serialize ( litExpr )
import Rel8.Query ( Query )
import Rel8.Query.Filter ( where_ )
import Rel8.Query.Maybe ( optional )
import Rel8.Query.Opaleye ( zipOpaleyeWith )
import Rel8.Table ( Table )
import Rel8.Table.Either ( EitherTable( EitherTable ) )
import Rel8.Table.Maybe ( MaybeTable( MaybeTable ), isJustTable )
import Rel8.Table.Opaleye ( unpackspec )
import Rel8.Table.Tag ( Tag(..) )
import Rel8.Table.These
  ( TheseTable( TheseTable )
  , hasHereTable, hasThereTable
  , isThisTable, isThatTable, isThoseTable
  )
import Rel8.Type.Tag ( EitherTag( IsLeft, IsRight ) )


-- | Corresponds to a @FULL OUTER JOIN@ between two queries.
alignBy :: (Table Expr a, Table Expr b)
  => (a -> b -> Expr Bool)
  -> Query a -> Query b -> Query (TheseTable a b)
alignBy condition as bs =
  uncurry TheseTable <$> zipOpaleyeWith fullOuterJoin as bs
  where
    fullOuterJoin a b =
      Opaleye.joinExplicit unpackspec unpackspec pure pure full a b on
      where
        full = Opaleye.FullJoin
        on = toColumn . toPrimExpr . uncurry condition


-- | Filter 'TheseTable's, keeping only 'thisTable's and 'thoseTable's.
keepHereTable :: TheseTable a b -> Query (a, MaybeTable b)
keepHereTable = loseThatTable


-- | Filter 'TheseTable's, keeping on
loseHereTable :: TheseTable a b -> Query b
loseHereTable = keepThatTable


keepThereTable :: TheseTable a b -> Query (MaybeTable a, b)
keepThereTable = loseThisTable


loseThereTable :: TheseTable a b -> Query a
loseThereTable = keepThisTable


keepThisTable :: TheseTable a b -> Query a
keepThisTable t@(TheseTable (MaybeTable _ a) _) = do
  where_ $ isThisTable t
  pure a


loseThisTable :: TheseTable a b -> Query (MaybeTable a, b)
loseThisTable t@(TheseTable ma (MaybeTable _ b)) = do
  where_ $ not_ $ isThisTable t
  pure (ma, b)


keepThatTable :: TheseTable a b -> Query b
keepThatTable t@(TheseTable _ (MaybeTable _ b)) = do
  where_ $ isThatTable t
  pure b


loseThatTable :: TheseTable a b -> Query (a, MaybeTable b)
loseThatTable t@(TheseTable (MaybeTable _ a) mb) = do
  where_ $ not_ $ isThatTable t
  pure (a, mb)


keepThoseTable :: TheseTable a b -> Query (a, b)
keepThoseTable t@(TheseTable (MaybeTable _ a) (MaybeTable _ b)) = do
  where_ $ isThoseTable t
  pure (a, b)


loseThoseTable :: TheseTable a b -> Query (EitherTable a b)
loseThoseTable t@(TheseTable (MaybeTable _ a) (MaybeTable _ b)) = do
  where_ $ not_ $ isThoseTable t
  pure $ EitherTable result a b
  where
    tag = boolExpr (litExpr IsLeft) (litExpr IsRight) (isThatTable t)
    result = (mempty `asTypeOf` result) {expr = tag}


bitraverseTheseTable :: ()
  => (a -> Query c)
  -> (b -> Query d)
  -> TheseTable a b
  -> Query (TheseTable c d)
bitraverseTheseTable f g t = do
  mc <- optional (f . fst =<< keepHereTable t)
  md <- optional (g . snd =<< keepThereTable t)
  where_ $ isJustTable mc ==. hasHereTable t
  where_ $ isJustTable md ==. hasThereTable t
  pure $ TheseTable mc md
