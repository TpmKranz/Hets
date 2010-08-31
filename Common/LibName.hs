{- |
Module      :  $Header$
Description :  library names for HetCASL and development graphs
Copyright   :  (c) Christian Maeder, DFKI GmbH 2008
License     :  GPLv2 or higher, see LICENSE.txt
Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

Abstract syntax of HetCASL specification libraries
   Follows Sect. II:2.2.5 of the CASL Reference Manual.
-}

module Common.LibName where

import Common.Doc
import Common.DocUtils
import Common.Id
import Common.Keywords
import Common.Utils

import Data.List
import System.Time

import Data.Graph.Inductive.Graph

omTs :: [Token]
omTs = [genToken "OM"]

mkQualName :: SIMPLE_ID -> LibId -> Id -> Id
mkQualName nodeId libId i =
  Id omTs [i, simpleIdToId nodeId, libIdToId libId] $ posOfId i

isQualNameFrom :: SIMPLE_ID -> LibId -> Id -> Bool
isQualNameFrom nodeId libId i@(Id _ cs _) = case cs of
  _ : n : l : _ | isQualName i ->
    n == simpleIdToId nodeId && libIdToId libId == l
  _ -> True

isQualName :: Id -> Bool
isQualName (Id ts cs _) = case cs of
  _ : _ : _ -> ts == omTs
  _ -> False

libIdOfQualName :: Id -> Id
libIdOfQualName j@(Id _ cs _) = case cs of
  [_, _, i] | isQualName j -> i
  _ -> error "libIdOfQualName: Check by isQualName before calling getLibId!"

getNodeId :: Id -> Id
getNodeId j@(Id _ cs _) = case cs of
  [_, i, _] | isQualName j -> i
  _ -> error "Check by isQualName before calling getNodeId!"


unQualName :: Id -> Id
unQualName j@(Id _ cs _) = case cs of
  i : _ | isQualName j -> i
  _ -> j

libIdToId :: LibId -> Id
libIdToId li = let
  path = splitOn '/' $ show li
  toTok s = Token s $ getRange li
  in mkId $ map toTok $ intersperse "/" path

data LibName = LibName
    { getLibId :: LibId
    , libVersion :: Maybe VersionNumber }

emptyLibName :: String -> LibName
emptyLibName s = LibName (IndirectLink s nullRange "" noTime) Nothing

data LibId =
    DirectLink URL Range
              -- pos: start of URL
  | IndirectLink PATH Range FilePath ClockTime
              -- pos: start of PATH

noTime :: ClockTime
noTime = TOD 0 0

-- | Returns the LibId of a LibName
getModTime :: LibId -> ClockTime
getModTime li = case li of
    DirectLink _ _ -> noTime
    IndirectLink _ _ _ m -> m

updFilePathOfLibId :: FilePath -> ClockTime -> LibId -> LibId
updFilePathOfLibId fp mt li = case li of
  DirectLink _ _ -> li
  IndirectLink p r _ _ -> IndirectLink p r fp mt

setFilePath :: FilePath -> ClockTime -> LibName -> LibName
setFilePath fp mt ln =
  ln { getLibId = updFilePathOfLibId fp mt $ getLibId ln }

getFilePath :: LibName -> FilePath
getFilePath ln =
    case getLibId ln of
      IndirectLink n _ fp _ ->
          if null fp then error "getFilePath: empty fp in " ++ n else fp
      _ -> error "getFilePath: No IndirectLink"

data VersionNumber = VersionNumber [String] Range
                      -- pos: "version", start of first string

type URL = String
type PATH = String

instance GetRange LibId where
  getRange li = case li of
    DirectLink _ r -> r
    IndirectLink _ r _ _ -> r

instance Show LibId where
  show li = case li of
    DirectLink s _ -> s
    IndirectLink s1 _ _ _ -> s1

instance GetRange LibName where
  getRange = getRange . getLibId

instance Show LibName where
  show = show . hsep . prettyLibName

prettyVersionNumber :: VersionNumber -> [Doc]
prettyVersionNumber (VersionNumber v _) =
  [keyword versionS, hcat $ punctuate dot $ map codeToken v]

prettyLibName :: LibName -> [Doc]
prettyLibName (LibName i mv) = pretty i : case mv of
        Nothing -> []
        Just v -> prettyVersionNumber v

instance Eq LibId where
  DirectLink s1 _ == DirectLink s2 _ = s1 == s2
  IndirectLink s1 _ _ _ == IndirectLink s2 _ _ _ = s1 == s2
  _ == _ = False

instance Ord LibId where
  DirectLink s1 _ <= DirectLink s2 _ = s1 <= s2
  IndirectLink s1 _ _ _ <= IndirectLink s2 _ _ _ = s1 <= s2
  DirectLink _ _ <= _ = True
  IndirectLink _ _ _ _ <= _ = False

instance Eq LibName where
  ln1 == ln2 = compare ln1 ln2 == EQ

instance Ord LibName where
  compare ln1 ln2 = compare (getLibId ln1) $ getLibId ln2

instance Pretty LibName where
    pretty = fsep . prettyLibName

instance Pretty LibId where
    pretty = structId . show

-- The Int type is used to represent Node, which is a typesynonym for Int.
-- We can't use Node here
data LinkPath a = LinkPath a [(LibId, Node)] deriving (Ord, Eq)

type SLinkPath = LinkPath String

showSLinkPath :: SLinkPath -> String
showSLinkPath (LinkPath x l) = s l where
    s ((_, n) : l1) = show n ++ "/" ++ s l1
    s _ = x

instance Show a => Show (LinkPath a) where
    show (LinkPath x l) = showSLinkPath $ LinkPath (show x) l

instance Functor LinkPath where
    fmap f (LinkPath x l) = LinkPath (f x) l

addToPath :: LibId -> Node -> LinkPath a -> LinkPath a
addToPath libid n (LinkPath x l) = LinkPath x $ (libid, n) : l

initPath :: LibId -> Node -> a -> LinkPath a
initPath libid n x = LinkPath x [(libid, n)]
