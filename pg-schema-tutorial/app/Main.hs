{-# LANGUAGE DuplicateRecordFields #-}
module Main where

import Control.Monad
import Data.Aeson
import Data.Aeson.TH
import Data.List as L
import Data.Text as T
import Data.Text.IO as T
import Database.PostgreSQL.Simple
import Database.PostgreSQL.Simple.FromField
import Database.PostgreSQL.Simple.ToField
import Generic.Random
import GHC.Generics
import Language.Haskell.TH
import PgSchema
import Sch
import Test.QuickCheck
import Test.QuickCheck.Instances ()

data Country = Country
  { code :: Maybe Text
  , name :: Text }
  -- TODO: cycle references lead to halt! Should check to avoid it
  -- , city_country :: SchList City }
  deriving (Eq, Show, Ord, Generic)

instance Arbitrary Country where
  arbitrary = genericArbitrarySingle

data City = City
  { name         :: Maybe Text
  , city_country :: Country }
  deriving (Eq, Show, Ord, Generic)

data Address = Address
  { street       :: Maybe Text
  , home         :: Maybe Text
  , app          :: Maybe Text
  , zipcode      :: Maybe Text
  , address_city :: City } -- PgTagged "name" (Maybe Text) }
  deriving (Eq, Show, Ord, Generic)

L.concat
  <$> zipWithM (\n s ->
    L.concat <$> sequenceA
      [ deriveJSON defaultOptions n
      , [d|instance FromRow $(conT n)|]
      , [d|instance ToRow $(conT n)|]
      , [d|instance FromField $(conT n) where fromField = fromJSONField |]
      , [d|instance ToField $(conT n) where toField = toJSONField |]
      , schemaRec @Sch id n
      , [d|instance CQueryRecord PG Sch $(litT $ strTyLit s) $(conT n)|]
      ])
  [ ''Country, ''City, ''Address]
  [ "countries", "cities", "addresses"]

main :: IO ()
main = do
  countries <- generate $ replicateM 5 (arbitrary @Country)
  mapM_ (\(a,b) -> T.putStrLn a >> print b)
    [ selectText @Sch @"countries" @Country qpEmpty
    , selectText @Sch @"cities" @City qpEmpty
    , selectText @Sch @"addresses" @Address qpEmpty
    , selectText @Sch @"addresses" @Address qp
    , selectText @Sch @"addresses" @Address qp'
    ]
  conn <- connectPostgreSQL "dbname=schema_test user=avia host=localhost"
  cids <- insertSch @Sch @"countries" conn countries
  mapM_ (print @(PgTagged "id" Int)) cids
  selectSch @Sch @"countries" @Country conn qpEmpty >>= print
  T.putStrLn ""
  selectSch @Sch @"cities" @City conn qpEmpty >>= print
  T.putStrLn ""
  selectSch @Sch @"addresses" @Address conn qpEmpty >>= print
  T.putStrLn ""
  selectSch @Sch @"addresses" @Address conn qp >>= print
  T.putStrLn ""
  selectSch @Sch @"addresses" @Address conn qp' >>= print
  where
    qp = qpEmpty
      { qpConds =
        [rootCond
          (pparent @"address_city"
            $ pparent @"city_country" (#code =? Just @Text "RU"))]
      , qpOrds = [ rootOrd [ascf @"street"] ] }
    qp' = qp { qpLOs = [rootLO $ LO (Just 1) (Just 1)] }
