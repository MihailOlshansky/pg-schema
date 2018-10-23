{-# LANGUAGE DuplicateRecordFields #-}
module Database.PostgreSQL.Schema.Info where

import Data.Aeson.TH
import Data.List as L
import Data.Text as T
import Database.PostgreSQL.Convert
import Database.PostgreSQL.DB
import Database.PostgreSQL.PgTagged
import Database.PostgreSQL.Schema.Catalog
import Database.PostgreSQL.Simple.FromRow
import Database.Schema.Rec
import Database.Schema.TH
import GHC.Generics


data PgClass = PgClass
-- ^ Tables and views info
  { class__namespace  :: PgTagged "nspname" Text
  , relname           :: Text
  , relkind           :: PgChar
  , attribute__class  :: SchList PgAttribute
  , constraint__class :: SchList PgConstraint }
  deriving (Show,Generic)

data PgAttribute = PgAttribute
  { attname         :: Text
  , attribute__type :: PgTagged "typname" Text
  , attnum          :: Int
  , attnotnull      :: Bool
  , atthasdef       :: Bool }
  deriving (Show,Generic)

data PgConstraint = PgConstraint
  { constraint__namespace :: PgTagged "nspname" Text
  , conname               :: Text
  , contype               :: PgChar
  , conkey                :: PgArr Int }
  deriving (Show,Generic)

data PgType = PgType
-- ^ Types info
  { oid             :: PgOid
  , type__namespace :: PgTagged "nspname" Text
  , typname         :: Text
  , typcategory     :: PgChar
  , typelem         :: PgOid
  , enum__type      :: SchList PgEnum}
  deriving (Show,Generic)

data PgEnum = PgEnum
  { enumlabel     :: Text
  , enumsortorder :: Double }
  deriving (Show,Generic)

data PgRelation = PgRelation
-- ^ Foreighn key info
  { constraint__namespace :: PgTagged "nspname" Text
  , conname               :: Text
  , constraint__class     :: PgTagged "relname" Text
  , constraint__fclass    :: PgTagged "relname" Text
  , conkey                :: PgArr Int
  , confkey               :: PgArr Int }
  deriving (Show,Generic)

L.concat <$> mapM (deriveJSON defaultOptions)
  [ ''PgEnum, ''PgType, ''PgConstraint, ''PgAttribute, ''PgClass, ''PgRelation]

L.concat <$> mapM (schemaRec @PgCatalog id)
  [ ''PgEnum, ''PgType, ''PgConstraint, ''PgAttribute, ''PgClass, ''PgRelation]

instance CQueryRecord PG PgCatalog "pg_enum" PgEnum
instance CQueryRecord PG PgCatalog "pg_constraint" PgConstraint
instance CQueryRecord PG PgCatalog "pg_attribute" PgAttribute
instance CQueryRecord PG PgCatalog "pg_class" PgClass
instance CQueryRecord PG PgCatalog "pg_type" PgType
instance CQueryRecord PG PgCatalog "pg_constraint" PgRelation

instance FromRow PgEnum
instance FromRow PgConstraint
instance FromRow PgAttribute
instance FromRow PgType
instance FromRow PgClass
instance FromRow PgRelation
