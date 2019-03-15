module Database.Schema.Gen where

import Data.List as L
import Data.Map as M
import Data.String
import Data.Text as T
import Database.Schema.Def
import Util.ShowType


mkInst :: ShowType a => Text -> [Text] -> a -> Text
mkInst name pars a
  =  "\ninstance C" <> sgn <> " where\n"
  <> "  type T" <> sgn <> " = \n"
  <> "    " <> showType a <> "\n"
  where
    sgn = T.intercalate " " (name : pars)


textTypDef :: Text -> Text -> TypDef -> Text
textTypDef sch typ td@(TypDef {..}) = mkInst "TypDef" ss td <> pgEnum
  where
    ss = [sch, showType typ]
    st = T.intercalate " " ss
    pgEnum
      | L.null typEnum = ""
      | otherwise
        =  "\ndata instance PGEnum " <> st <> " = \n"
        <> "  " <> T.intercalate " | " (((toTitle typ <> "_") <>) <$> typEnum)
        <> "\n"
        <> "  deriving (Show, Read, Ord, Eq, Generic)\n"

textFldDef :: Text -> Text -> Text -> FldDef -> Text
textFldDef sch tab fld =
  mkInst "FldDef" [sch, showType tab, showType fld]

textTabDef :: Text -> Text -> TabDef -> Text
textTabDef sch tab = mkInst "TabDef" [sch, showType tab]

textRelDef :: Text -> Text -> RelDef -> Text
textRelDef sch rel = mkInst "RelDef" [sch, showType rel]

genModuleText
  :: Text -- ^ module name
  -> Text -- ^ schema name
  -> Text -- ^ database schema name
  -> Int  -- ^ schema hash value
  -> (Map Text TypDef
    , Map (Text,Text) FldDef
    , Map Text TabDef
    , Map Text RelDef)
  -> Text
genModuleText moduleName schName dbSchName hash (mtyp, mfld, mtab, mrel)
  =  "{-# OPTIONS_GHC -fno-warn-unused-top-binds #-}\n"
  <> "{-# OPTIONS_GHC -fno-warn-unused-imports #-}\n"
  <> "module " <> moduleName <> "(" <> schName <> ") where\n\n"
  <> "-- This file is generated and can't be edited.\n\n"
  <> "import GHC.Generics\n"
  <> "import PgSchema\n\n\n"
  <> "hashSchema :: Int\n"
  <> "hashSchema = " <> fromString (show hash) <> "\n\n"
  <> "data " <> schName <> "\n\n"
  <> (mconcat $ L.map (uncurry $ textTypDef schName) $ toList mtyp)
  <> (mconcat $ L.map (\((a,b),c) -> textFldDef schName a b c) $ toList mfld)
  <> (mconcat $ L.map (uncurry $ textTabDef schName) $ toList mtab)
  <> (mconcat $ L.map (uncurry $ textRelDef schName) $ toList mrel)
  <> "\ninstance CSchema " <> schName <> " where\n"
  <> "  type TSchema " <> schName <> " = " <> showType dbSchName <> "\n"
  <> "  type TTabs " <> schName <> " = " <> showType (keys mtab) <> "\n"
  <> "  type TRels " <> schName <> " = " <> showType (keys mrel) <> "\n"
  <> "  type TTypes " <> schName <> " = " <> showType (keys mtyp) <> "\n"
