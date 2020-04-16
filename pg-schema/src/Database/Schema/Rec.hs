{-# LANGUAGE UndecidableInstances    #-}
{-# LANGUAGE UndecidableSuperClasses #-}
module Database.Schema.Rec where

import Data.Kind
import Data.List as L
import Data.Singletons.Prelude as SP hiding ((:.))
import Data.Singletons.Prelude.List as SP
import Data.Singletons.TH hiding ((:.))
import Data.Text (Text)
import Database.PostgreSQL.Simple.Types as PG
import Database.Schema.Def
import PgSchema.Util


singletons [d|
  data FieldInfo' s = FieldInfo
    { fieldName :: s
    , fieldDbName :: s }
    deriving Show
  |]

promote [d|
  fiWithType :: (s -> t) -> [FieldInfo' s] -> [(FieldInfo' s, t)]
  fiWithType f = map (\fi -> (fi, f $ fieldName fi))

  riFieldType
    :: Eq s
    => (s -> t) -> (s -> t) -> [FieldInfo' s] -> [FieldInfo' s] -> s -> t
  riFieldType f1 f2 rs1 rs2 n = find1 rs1
    where
      find1 []     = find2 rs2
      find1 (x:xs) = if fieldName x == n then f1 n else find1 xs
      find2 []     = error "riFieldType: No field found"
      find2 (x:xs) = if fieldName x == n then f2 n else find2 xs

  orField :: Eq s => [FieldInfo' s] -> [FieldInfo' s] -> s -> Bool
  orField rs1 rs2 n = find1 rs1
    where
      find1 []     = find2 rs2
      find1 (x:xs) = fieldName x == n || find1 xs
      find2 []     = False
      find2 (x:xs) = fieldName x == n || find2 xs
  |]

type FieldInfoK = FieldInfo' Symbol
type FieldInfo = FieldInfo' Text

-- | instances will be generated by TH
class CFieldType (r :: Type) (n :: Symbol) where
  type TFieldType r n :: Type

genDefunSymbols [''TFieldType]

instance OrField (TRecordInfo r1) (TRecordInfo r2) n ~ 'True
  => CFieldType (r1 PG.:. r2) n where
  type TFieldType (r1 PG.:. r2) n = RiFieldType
    (TFieldTypeSym1 r1) (TFieldTypeSym1 r2) (TRecordInfo r1) (TRecordInfo r2) n

-- | instances will be generated by TH
class ToStar (TRecordInfo r) => CRecordInfo r where
  type TRecordInfo r :: [FieldInfoK]

instance (CRecordInfo r1, CRecordInfo r2, ToStar (TRecordInfo (r1 PG.:. r2)))
  => CRecordInfo (r1 PG.:. r2) where
  type TRecordInfo (r1 PG.:. r2) = TRecordInfo r1 ++ TRecordInfo r2

instance
  ( CQueryRecord db sch t r1, CQueryRecord db sch t r2
  , CQueryFields db sch t (FiTypeInfo (r1 :. r2))
  )
  => CQueryRecord db sch t (r1 :. r2)

recordInfo :: forall r. CRecordInfo r => [FieldInfo]
recordInfo = demote @(TRecordInfo r)

data QueryRecord = QueryRecord
  { tableName   :: NameNS
  , queryFields :: [QueryField] }
  deriving Show

data QueryRef = QueryRef
  { fromName :: Text
  , fromDef  :: FldDef
  , toName   :: Text
  , toDef    :: FldDef }
  deriving Show

data QueryField
  = FieldPlain Text Text FldDef -- name dbname flddef
  | FieldTo    Text Text QueryRecord [QueryRef]
  | FieldFrom  Text Text QueryRecord [QueryRef]
  deriving Show

type FiTypeInfo r = FiWithType (TFieldTypeSym1 r) (TRecordInfo r)
class
  ( CSchema sch, ToStar t, CQueryFields db sch t (FiTypeInfo r) )
  => CQueryRecord (db::Type) (sch::Type) (t::NameNSK) (r::Type) where
  getQueryRecord :: QueryRecord
  getQueryRecord = QueryRecord {..}
    where
      tableName = demote @t
      queryFields = getQueryFields
        @db @sch @t @(FiWithType (TFieldTypeSym1 r) (TRecordInfo r))

class CTypDef sch tn => CanConvert db sch (tn::NameNSK) (nullable::Bool) t

class
  (CSchema sch, CTabDef sch t)
  => CQueryFields db sch (t::NameNSK) (fis :: [(FieldInfoK,Type)]) where
  getQueryFields :: [QueryField]

class CQueryFieldT (ft::FldKindK) db sch (t::NameNSK) (fi::(FieldInfoK,Type))
  where
    getQueryFieldT :: QueryField
--
class CQueryFieldTB (nullable:: Bool) rd db sch t (fi::(FieldInfoK,Type))
  where
    getQueryFieldTB :: QueryField

instance CQueryFieldTB (IsMaybe r) rd db sch t '(fi, r)
  => CQueryFieldT ('FldFrom rd) db sch t '(fi, r) where
  getQueryFieldT = getQueryFieldTB @(IsMaybe r) @rd @db @sch @t @'(fi, r)

instance (CSchema sch, CTabDef sch t) => CQueryFields db sch t '[] where
  getQueryFields = []

type family IsMaybe (x :: Type) :: Bool where
  IsMaybe (Maybe a) = 'True
  IsMaybe x = 'False

instance
  ( CQueryFieldT (TFieldKind sch t (FieldDbName (Fst x))) db sch t x
  , CQueryFields db sch t xs
  , CSchema sch, CTabDef sch t )
  => CQueryFields db sch t (x ': xs) where
  getQueryFields
    = getQueryFieldT @(TFieldKind sch t (FieldDbName (Fst x))) @db @sch @t @x
    : getQueryFields @db @sch @t @xs

instance
  ( CFldDef sch t dbname
  , fdef ~ TFldDef sch t dbname
  , CanConvert db sch (FdType fdef) (FdNullable fdef) ftype
  , ToStar n )
  => CQueryFieldT 'FldPlain db sch t '( 'FieldInfo n dbname, ftype) where
  getQueryFieldT =
    FieldPlain (demote @n) (demote @dbname) (fldDef @sch @t @dbname)

instance
  ( tabTo ~ RdTo rd
  , CQueryRecord db sch tabTo recTo
  , cols ~ RdCols rd
  , ToStar cols
  , uncols ~ Unzip cols
  , fds ~ SP.Map (TFldDefSym2 sch t) (Fst uncols)
  , HasNullable fds ~ 'False
  , fdsTo ~ SP.Map (TFldDefSym2 sch tabTo) (Snd uncols)
  , ToStar fds
  , ToStar fdsTo
  , ToStar n
  , ToStar dbname )
  => CQueryFieldTB 'False rd db sch t '( 'FieldInfo n dbname, recTo)
  where
  getQueryFieldTB =
    FieldFrom (demote @n) (demote @dbname)
      (getQueryRecord @db @sch @tabTo @recTo) refs
    where
      refs = zipWith3 (\(fromName,toName) fromDef toDef -> QueryRef {..})
        (demote @cols) (demote @fds) (demote @fdsTo)
--
instance
  ( tabTo ~ RdTo rd
  , CQueryRecord db sch tabTo recTo
  , cols ~ RdCols rd
  , ToStar cols
  , uncols ~ Unzip cols
  , fds ~ SP.Map (TFldDefSym2 sch t) (Fst uncols)
  , fdsTo ~ SP.Map (TFldDefSym2 sch tabTo) (Snd uncols)
  , ToStar fds
  , ToStar fdsTo
  , ToStar n
  , ToStar dbname )
  => CQueryFieldTB 'True rd db sch t '( 'FieldInfo n dbname, Maybe recTo)
  where
  getQueryFieldTB =
    FieldFrom (demote @n) (demote @dbname)
      (getQueryRecord @db @sch @tabTo @recTo) refs
    where
      refs = zipWith3 (\(fromName,toName) fromDef toDef -> QueryRef {..})
        (demote @cols) (demote @fds) (demote @fdsTo)

instance
  ( tabFrom ~ RdFrom rd
  , CQueryRecord db sch tabFrom recFrom
  , cols ~ RdCols rd
  , ToStar cols
  , uncols ~ Unzip cols
  , fds ~ SP.Map (TFldDefSym2 sch t) (Snd uncols)
  , fdsFrom ~ SP.Map (TFldDefSym2 sch tabFrom) (Fst uncols)
  , ToStar fds
  , ToStar fdsFrom
  , ToStar n
  , ToStar dbname )
  => CQueryFieldT ('FldTo rd) db sch t '( 'FieldInfo n dbname, recFrom) where
  getQueryFieldT =
    FieldTo (demote @n) (demote @dbname)
      (getQueryRecord @db @sch @tabFrom @recFrom) refs
    where
      refs = zipWith3 (\(fromName,toName) fromDef toDef -> QueryRef {..})
        (demote @cols) (demote @fdsFrom) (demote @fds)
type AllMandatory sch t r =
  IsAllMandatory sch t (Map FieldDbNameSym0 (TRecordInfo r)) ~ 'True
