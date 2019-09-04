module PgSchema.Gen where

import Data.Foldable as F
import Data.List as L
import Data.Map as M
import Data.Text as T
import PgSchema
import Util.ToStar


data DotOper
  = ExcludeToTab NameNS Text


genDot :: forall sch. CSchema sch => Bool -> [DotOper] -> Text
genDot isQual dos = F.fold
  [ "digraph G {\n"
  , "  penwidth=2\n\n"
  , F.fold dbSchemas
  , ""
  , T.unlines relTxts
  , "}\n"
  ]
  where
    tabs = toStar @(TTabs sch)
    rels = L.concatMap elems . elems $ tiFrom <$> tabInfoMap @sch
    tabsByName = M.fromListWith (<>)
      $ ((,) <$> nnsName <*> ((:[]) . nnsNamespace)) <$> tabs
    qName nns
      | isQual    = q
      | otherwise = case M.lookup (nnsName nns) tabsByName of
        Just [_] -> (nnsName nns,False)
        _        -> q
      where
        q = (qualName nns,True)
    qNameQuo nns = case qName nns of
      (x,False) -> x
      (x,True)  -> "\"" <> x <> "\""
    qName' nns = case exTo of
      [] -> nns'
      _  -> nns' <> " [label=\"" <> fst (qName nns) <> ": "
        <> (T.unwords exTo) <> "\"]"
      where
        nns' = qNameQuo nns
        exTo = [t | ExcludeToTab x t <- dos, RelDef {..} <- rels
          , rdTo == x, rdFrom == nns]
    dbSchemas = dbSchema <$> nub (nnsNamespace <$> tabs)
    dbSchema schName = F.fold
      [ "  subgraph cluster_" <> schName <> "{\n"
      , "    label=\"" <> schName <> "\"\n"
      , T.unlines
        $ ("    " <>) . qName' <$> L.filter ((==schName) . nnsNamespace) tabs
      , "  }\n"
      ]
    relTxts = rel <$> L.filter notExcluded rels
      where
        notExcluded RelDef{..} = L.null [()|ExcludeToTab x _ <- dos, rdTo ==x]
    rel RelDef {..} = "  " <> qNameQuo rdFrom <> "->" <> qNameQuo rdTo