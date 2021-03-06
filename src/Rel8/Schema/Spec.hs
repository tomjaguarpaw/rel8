{-# language DataKinds #-}
{-# language FlexibleContexts #-}
{-# language GADTs #-}
{-# language StandaloneKindSignatures #-}
{-# language UndecidableInstances #-}

module Rel8.Schema.Spec
  ( Spec( Spec )
  , SSpec( SSpec, labels, info, nullity )
  , KnownSpec( specSing )
  )
where

-- base
import Data.Kind ( Constraint, Type )
import Prelude ()

-- rel8
import Rel8.Kind.Labels ( Labels, SLabels, KnownLabels, labelsSing )
import Rel8.Schema.Null ( Nullity, Sql, Unnullify, nullable )
import Rel8.Type ( DBType, typeInformation )
import Rel8.Type.Information ( TypeInformation )


type Spec :: Type
data Spec = Spec Labels Type


type SSpec :: Spec -> Type
data SSpec spec where
  SSpec ::
    { labels :: SLabels labels
    , info :: TypeInformation (Unnullify a)
    , nullity :: Nullity a
    }
    -> SSpec ('Spec labels a)


type KnownSpec :: Spec -> Constraint
class KnownSpec spec where
  specSing :: SSpec spec


instance
  ( KnownLabels labels
  , Sql DBType a
  )
  => KnownSpec ('Spec labels a)
 where
  specSing = SSpec
    { labels = labelsSing
    , info = typeInformation
    , nullity = nullable
    }
