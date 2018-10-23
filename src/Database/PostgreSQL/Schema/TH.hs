module Database.PostgreSQL.Schema.TH where

import Control.Monad.Zip
import Data.Bifunctor
import Data.ByteString (ByteString)
import Data.Coerce
import Data.List as L
import Data.Map as M
import Data.Maybe as Mb
import Data.Ord
import Data.Set as S
import Data.Text as T
import Database.PostgreSQL.Convert
import Database.PostgreSQL.DML.Select
import Database.PostgreSQL.PgTagged
import Database.PostgreSQL.Schema.Catalog
import Database.PostgreSQL.Schema.Info
import Database.PostgreSQL.Simple
import Database.Schema.Def
import Database.Schema.Rec
import Database.Schema.TH
import Language.Haskell.TH


mkSchema :: ByteString -> Name -> Text -> DecsQ
mkSchema connStr sch ns = do
  (types, classes, relations) <- runIO $ do
    conn <- connectPostgreSQL connStr
    types <- selectSch_ @PgCatalog @"pg_type" @PgType conn
    (classes::[PgClass]) <- fmap attFilterAndSort <$> query conn
      ("select * from ("
        <> selectQuery @PgCatalog @"pg_class" @PgClass <> ") t \
        \where t.class__namespace=jsonb_build_object('nspname',?) \
        \and t.relkind in ('v','r')")
      (Only ns)
    (relations::[PgRelation]) <- query conn
      ("select * from ("
        <> selectQuery @PgCatalog @"pg_constraint" @PgRelation <> ") t \
        \where t.constraint__namespace=jsonb_build_object('nspname',?)")
      (Only ns)
    pure (types, classes, relations)

  let
    classAttrs = ((,) <$> relname <*> getSchList . attribute__class) <$> classes
    mClassAttrs =
      M.fromList [((c, attnum a), attname a)| (c,as) <- classAttrs, a <- as]
    attrs = L.concat $ (\(a,xs) -> (a,) <$> xs) <$> classAttrs
    attrsTypes = S.fromList $ (unPgTag . attribute__type . snd) <$> attrs
    mtypes = M.fromList . fmap (\x -> (oid x, x)) $ types
    ntypes = (\t -> (t, unpack . typname <$> M.lookup (typelem t) mtypes))
      <$> L.filter ((`S.member` attrsTypes) . typname) types

  -- reportWarning $ "ntypes count: " ++ show (L.length ntypes)
  -- reportWarning $ "attrs count: " ++ show (L.length attrs)
  typs <- L.concat <$> traverse instTypDef ntypes
  flds <- L.concat <$> traverse instFldDef attrs
  tabs <- L.concat <$> traverse instTabDef classes
  rls <- fmap L.concat . traverse instRelDef
    $ Mb.mapMaybe (mkRelDef mClassAttrs) relations
  schema <- instSchema (relname <$> classes)
    ((\PgRelation {..} -> conname) <$> relations)
  pure $ typs ++ flds ++ tabs ++ rls ++ schema
  where
    attFilterAndSort c =
      c { attribute__class = coerce $ L.sortBy (comparing attnum)
        $ L.filter ((>0) . attnum) (coerce $ attribute__class c) }
    schQ = conT sch
    instTypDef (pgt,mbn) = [d|
      instance CTypDef $(schQ) $(nameQ) where
        type TTypDef $(schQ) $(nameQ) =
          'TypDef $(categoryQ) $(typElemQ) $(enumQ)
      |]
      where
        nameQ = pure $ strToSym $ unpack $ typname pgt
        categoryQ = pure $ strToSym [coerce $ typcategory pgt]
        enumQ
          = pure . toPromotedList . getSchList
          $ strToSym . unpack . enumlabel <$> enum__type pgt
        typElemQ = toPromotedMaybeQ $ strToSym <$> mbn
    instFldDef (cname, attr) = [d|
      instance CFldDef $(schQ) $(tabQ) $(fldQ) where
        type TFldDef $(schQ) $(tabQ) $(fldQ) =
          'FldDef $(typQ) $(nulQ) $(defQ)
      |]
      where
        tabQ = pure $ strToSym $ unpack cname
        fldQ = pure $ strToSym $ unpack $ attname attr
        typQ = pure $ strToSym $ unpack $ unPgTag $ attribute__type attr
        nulQ = boolQ $ not $ attnotnull attr
        defQ = boolQ $ atthasdef attr
    instTabDef PgClass {..} = [d|
      instance CTabDef $(schQ) $(tabQ) where
        type TTabDef $(schQ) $(tabQ) =
          'TabDef $(fsQ) $(pkQ) $(ukQ)
      |]
      where
        tabQ = pure $ strToSym $ unpack relname
        attrs = getSchList attribute__class
        constrs = getSchList constraint__class
        fsQ = pure . toPromotedList $ strToSym . unpack . attname <$> attrs
        numToSym a =
          strToSym . unpack . attname <$> L.find ((==a) . attnum) attrs
        keysBy f
          = catMaybes -- if something is wrong exclude such constraint
          $ traverse numToSym . (\PgConstraint {..} -> getPgArr conkey)
          <$> L.filter (f . coerce . contype) constrs
        pkQ = pure . toPromotedList . L.concat $ keysBy (=='p')
        ukQ = pure . toPromotedList $ toPromotedList <$> keysBy (=='u')
    mkRelDef mClassAttrs PgRelation {..} = sequenceA
      ( conname
      , RelDef
        <$> pure fromName
        <*> pure toName
        <*> sequenceA (getPgArr $ mzipWith getName2 conkey confkey) )
      where
        fromName = unPgTag constraint__class
        toName = unPgTag constraint__fclass
        getName t n = M.lookup (t,n) mClassAttrs
        getName2 n1 n2 = (,) <$> getName fromName n1 <*> getName toName n2
    instRelDef (c, RelDef {..}) = [d|
      instance CRelDef $(schQ) $(relQ) where
        type TRelDef $(schQ) $(relQ) =
          'RelDef $(fromQ) $(toQ) $(colsQ)
      |]
      where
        relQ = pure $ txtToSym c
        fromQ = pure $ txtToSym rdFrom
        toQ = pure $ txtToSym rdTo
        colsQ
          = fmap toPromotedList . traverse pairQ
          $ bimap txtToSym txtToSym <$> rdCols

    instSchema ts rs = [d|
      instance CSchema $(schQ) where
        type TSchema $(schQ) = $(pure $ txtToSym ns)
        type TTabs $(schQ) = $(pure $ toPromotedList $ L.map txtToSym ts)
        type TRels $(schQ) = $(pure $ toPromotedList $ L.map txtToSym rs)
      |]

    -- class CSchema sch where
    --   type TSchema sch  :: Symbol
    --   type TTabs sch    :: [Symbol]
    --   type TRels sch    :: [Symbol]

    --
    -- data RelDef' s = RelDef
    --   { rdFrom    :: s
    --   , rdTo      :: s
    --   , rdCols    :: [(s,s)]
    --   , rdDelCons :: DelCons }

toPromotedMaybeQ :: Maybe Type -> TypeQ
toPromotedMaybeQ Nothing  = [t|'Nothing|]
toPromotedMaybeQ (Just t) = appT [t|'Just|] (pure t)

boolQ :: Bool -> TypeQ
boolQ True  = [t|'True|]
boolQ False = [t|'False|]

pairQ :: (Type,Type) -> TypeQ
pairQ (a,b) = [t| '( $(pure a), $(pure b) )|]
