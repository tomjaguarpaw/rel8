{-# language BlockArguments #-}
{-# language DisambiguateRecordFields #-}
{-# language FlexibleContexts #-}
{-# language LambdaCase #-}
{-# language NamedFieldPuns #-}
{-# language TypeFamilies #-}
{-# language ViewPatterns #-}

module Rel8.Table.Opaleye
  ( aggregator
  , binaryspec
  , distinctspec
  , table
  , tableFields
  , unpackspec
  , valuesspec
  , castTable
  )
where

-- base
import Prelude hiding ( undefined )

-- opaleye
import qualified Opaleye.Internal.Aggregate as Opaleye
import qualified Opaleye.Internal.Binary as Opaleye
import qualified Opaleye.Internal.Distinct as Opaleye
import qualified Opaleye.Internal.HaskellDB.PrimQuery as Opaleye
import qualified Opaleye.Internal.PackMap as Opaleye
import qualified Opaleye.Internal.Unpackspec as Opaleye
import qualified Opaleye.Internal.Values as Opaleye
import qualified Opaleye.Internal.Table as Opaleye

-- profunctors
import Data.Profunctor ( dimap, lmap )

-- rel8
import Rel8.Aggregate ( Col( A ), Aggregate( Aggregate ), Aggregates )
import Rel8.Expr ( Expr, Col(..) )
import Rel8.Expr.Opaleye
  ( fromPrimExpr, toPrimExpr
  , traversePrimExpr
  , fromColumn, toColumn
  , scastExpr
  )
import Rel8.Schema.HTable ( htabulateA, hfield, htraverse, hspecs, htabulate )
import Rel8.Schema.Name ( Col( N ), Name( Name ), Selects )
import Rel8.Schema.Spec ( SSpec(..) )
import Rel8.Schema.Table ( TableSchema(..) )
import Rel8.Table ( Table, fromColumns, toColumns )
import Rel8.Table.Undefined ( undefined )

-- semigroupoids
import Data.Functor.Apply ( WrappedApplicative(..) )


aggregator :: Aggregates aggregates exprs => Opaleye.Aggregator aggregates exprs
aggregator = Opaleye.Aggregator $ Opaleye.PackMap $ \f aggregates ->
  fmap fromColumns $ unwrapApplicative $ htabulateA $ \field ->
    WrapApplicative $ case hfield (toColumns aggregates) field of
      A (Aggregate (Opaleye.Aggregator (Opaleye.PackMap inner))) ->
        E <$> inner f ()


binaryspec :: Table Expr a => Opaleye.Binaryspec a a
binaryspec = Opaleye.Binaryspec $ Opaleye.PackMap $ \f (as, bs) ->
  fmap fromColumns $ unwrapApplicative $ htabulateA $ \field ->
    WrapApplicative $
      case (hfield (toColumns as) field, hfield (toColumns bs) field) of
        (E a, E b) -> E . fromPrimExpr <$> f (toPrimExpr a, toPrimExpr b)


distinctspec :: Table Expr a => Opaleye.Distinctspec a a
distinctspec =
  Opaleye.Distinctspec $ Opaleye.Aggregator $ Opaleye.PackMap $ \f ->
    fmap fromColumns .
    unwrapApplicative .
    htraverse
      (\(E a) ->
         WrapApplicative $ E . fromPrimExpr <$> f (Nothing, toPrimExpr a)) .
    toColumns


table ::Selects names exprs => TableSchema names -> Opaleye.Table exprs exprs
table (TableSchema name schema columns) =
  case schema of
    Nothing -> Opaleye.Table name (tableFields columns)
    Just schemaName -> Opaleye.TableWithSchema schemaName name (tableFields columns)


tableFields ::Selects names exprs
  => names -> Opaleye.TableFields exprs exprs
tableFields (toColumns -> names) = dimap toColumns fromColumns $
  unwrapApplicative $ htabulateA $ \field -> WrapApplicative $
    case hfield names field of
      name -> lmap (`hfield` field) (go name)
  where
    go :: Col Name spec -> Opaleye.TableFields (Col Expr spec) (Col Expr spec)
    go (N (Name name)) =
      lmap (\(E a) -> toColumn $ toPrimExpr a) $
        E . fromPrimExpr . fromColumn <$>
          Opaleye.requiredTableField name


unpackspec :: Table Expr a => Opaleye.Unpackspec a a
unpackspec = Opaleye.Unpackspec $ Opaleye.PackMap $ \f ->
  fmap fromColumns .
  unwrapApplicative .
  htraverse (\(E a) -> WrapApplicative $ E <$> traversePrimExpr f a) .
  toColumns
{-# INLINABLE unpackspec #-}


valuesspec :: Table Expr a => Opaleye.ValuesspecSafe a a
valuesspec = Opaleye.ValuesspecSafe (toPackMap undefined) unpackspec


toPackMap :: Table Expr a
  => a -> Opaleye.PackMap Opaleye.PrimExpr Opaleye.PrimExpr () a
toPackMap as = Opaleye.PackMap $ \f () ->
  fmap fromColumns $
  unwrapApplicative .
  htraverse (\(E a) -> WrapApplicative $ E <$> traversePrimExpr f a) $
  toColumns as


-- | Transform a table by adding 'CAST' to all columns. This is most useful for
-- finalising a SELECT or RETURNING statement, guaranteed that the output
-- matches what is encoded in each columns TypeInformation.
castTable :: Table Expr a => a -> a
castTable (toColumns -> as) = fromColumns $ htabulate \i ->
  case hfield hspecs i of
    SSpec{info} -> 
      case hfield as i of
        E expr ->
          E (scastExpr info expr)
