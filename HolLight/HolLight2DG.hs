{- |
Module      :  $Header$
Description :  Import data generated by hol2hets into a DG
Copyright   :  (c) Jonathan von Schroeder, DFKI GmbH 2010
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  jonathan.von_schroeder@dfki.de
Stability   :  experimental
Portability :  portable

-}

module HolLight.HolLight2DG where

import Static.GTheory
import Static.DevGraph

import Static.DgUtils
import Static.History
import Static.ComputeTheory

import Logic.Logic
import Logic.Prover
import Logic.ExtSign
import Logic.Grothendieck

import Common.LibName
import Common.Id
import Common.AS_Annotation
import Common.Result
import Common.Utils (getTempFile,getEnvDef)

import HolLight.Sign
import HolLight.Sentence
import HolLight.Term
import HolLight.Logic_HolLight

import HolLight.Helper(names)

import Driver.Options

import Data.Graph.Inductive.Graph
import qualified Data.Map as Map
import qualified Data.Char

import System.FilePath.Posix
import System.Directory (removeFile,canonicalizePath)

import Text.XML.Expat.SAX
import qualified Data.ByteString.Lazy as L

import qualified System.Process as SP

type SaxEvL = [SAXEvent String String]

parsexml :: L.ByteString -> SaxEvL
parsexml txt = parse defaultParseOptions txt

is_space :: String -> Bool
is_space = all Data.Char.isSpace

tag :: SaxEvL -> SaxEvL
tag = dropWhile (\e -> case e of
                        (CharacterData d) -> is_space d
                        _ -> False)

dropSpaces :: SaxEvL -> SaxEvL
dropSpaces = tag

whileJust :: b -> (b -> (Maybe a,b)) -> (Maybe [a],b)
whileJust d f =
 case f d of
  (Just r,d') ->
   case whileJust d' f of
     (Just l,d'') -> (Just (r:l),d'')
     _ -> (Just [r],d')
  _ -> (Just [],d)

readL :: (SaxEvL -> (Maybe a,SaxEvL)) -> String -> SaxEvL -> (Maybe [a],SaxEvL)
readL f s d = case tag d of
 ((StartElement s' _):d') -> if (s'/=s) then (Nothing,d) else case whileJust d' f of
  (Just l,d'') -> case tag d'' of
   ((EndElement s''):d''') -> if (s''/=s) then (Nothing,d) else (Just l,d''')
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 _ -> (Nothing,d)

--reads list in reverse
readList' :: (SaxEvL -> (Maybe a,SaxEvL)) -> SaxEvL -> (Maybe [a],SaxEvL)
readList' f d = case whileJust d f of
 (Just l,d') -> (Just l,d')
 _ -> (Nothing,d)

whileJust' :: b -> (b -> a -> (Maybe a,b)) -> a -> (Maybe a,b)
whileJust' d f s = case f d s of
 (Just s',d') -> case whileJust' d' f s' of
  r@(Just _,_) -> r
  _ -> (Just s',d')
 _ -> (Nothing,d)

foldS :: (SaxEvL -> b -> (Maybe b,SaxEvL)) -> b -> String -> SaxEvL -> (Maybe b,SaxEvL)
foldS f b s d = case tag d of
 ((StartElement s' _):d') -> if (s'/=s) then (Nothing,d) else case whileJust' d' f b of
  (Just b',d'') -> case tag d'' of
   ((EndElement s''):d''') -> if (s''/=s) then (Nothing,d) else (Just b',d''')
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 _ -> (Nothing,d)

readTuple :: (Show a,Show b) => (SaxEvL -> (Maybe a,SaxEvL)) -> (SaxEvL -> (Maybe b,SaxEvL)) -> SaxEvL -> (Maybe (a,b),SaxEvL)
readTuple f1 f2 d = case tag d of
 ((StartElement "tuple" _):d1) -> case tag d1 of
  ((StartElement "fst" _):d2) -> case f1 d2 of
   (Just r1,d3) -> case tag d3 of
    ((EndElement "fst"):d4) -> case tag d4 of
     ((StartElement "snd" _):d5) -> case f2 d5 of
      (Just r2,d6) -> case tag d6 of
       ((EndElement "snd"):d7) -> case tag d7 of
        ((EndElement "tuple"):d8) -> (Just (r1,r2),d8)
        _ -> (Nothing,d)
       _ -> (Nothing,d)
      _ -> (Nothing,d)

     _ -> (Nothing,d)
    _ -> (Nothing,d)
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 _ -> (Nothing,d)

readTuple' :: (SaxEvL -> (Maybe a,SaxEvL)) -> (SaxEvL -> a -> b -> (Maybe b,SaxEvL)) -> SaxEvL -> b -> (Maybe b,SaxEvL)
readTuple' f1 f2 d b = case tag d of
 ((StartElement "tuple" _):d1) -> case tag d1 of
  ((StartElement "fst" _):d2) -> case f1 d2 of
   (Just r1,d3) -> case tag d3 of
    ((EndElement "fst"):d4) -> case tag d4 of
     ((StartElement "snd" _):d5) -> case f2 d5 r1 b of
      (Just r2,d6) -> case tag d6 of
       ((EndElement "snd"):d7) -> case tag d7 of
        ((EndElement "tuple"):d8) -> (Just r2,d8)
        _ -> (Nothing,d)
       _ -> (Nothing,d)
      _ -> (Nothing,d)
     _ -> (Nothing,d)
    _ -> (Nothing,d)
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 _ -> (Nothing,d)

readWord' :: SaxEvL -> (Maybe String, SaxEvL)
readWord' d = case d of
 ((CharacterData s):d') -> let b = Data.Char.isSpace
                           in case readWord' d' of
                              (Just s',d'') -> (Just (reverse (dropWhile b (reverse (dropWhile b (s++s'))))),d'')
                              _ -> (Just (reverse (dropWhile b (reverse (dropWhile b s)))),d')
 _ -> (Nothing,d)


readWord :: SaxEvL -> (Maybe String,SaxEvL)
readWord d = case dropSpaces d of
 ((CharacterData s):d') -> let b = Data.Char.isSpace
                           in case readWord' d' of
                              (Just s',d'') -> (Just (reverse (dropWhile b (reverse (dropWhile b (s++s'))))),d'')
                              _ -> (Just (reverse (dropWhile b (reverse (dropWhile b s)))),d')
 _ -> (Nothing,d)

readStr :: SaxEvL -> (Maybe String,SaxEvL)
readStr d = case tag d of
 ((StartElement "s" _):d') -> case readWord d' of
  (Just s,d'') -> case tag d'' of
   ((EndElement "s"):d''') -> (Just s,d''')
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 _ -> (Nothing,d)

readInt :: SaxEvL -> (Maybe Int,SaxEvL)
readInt d = case readWord d of
 (Just s,d') -> (Just ((read s)::Int),d')
 _ -> (Nothing,d)

readInt' :: SaxEvL -> (Maybe Int,SaxEvL)
readInt' d = case tag d of
 ((StartElement "i" _):d') -> case readInt d' of
  (Just i,d'') -> case tag d'' of
   ((EndElement "i"):d''') -> (Just i,d''')
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 _ -> (Nothing,d)

readMappedInt :: Map.Map Int a -> SaxEvL -> (Maybe a,SaxEvL)
readMappedInt m d = case readInt d of
 (Just i,d') -> case Map.lookup i m of
  (Just a) -> (Just a,d')
  _ -> (Nothing,d)
 _ -> (Nothing,d)

listToTypes :: Map.Map Int HolType -> [Int] -> Maybe [HolType]
listToTypes m l = case l of
 (x:xs) -> case Map.lookup x m of
  (Just t) -> case listToTypes m xs of
   (Just ts) -> Just (t:ts)
   _ -> Nothing
  _ -> Nothing
 []     -> Just []


readSharedHolType :: Map.Map Int String -> SaxEvL -> Map.Map Int HolType -> (Maybe (Map.Map Int HolType),SaxEvL)

readSharedHolType sl d m = case tag d of
 ((StartElement "TyApp" _):d1) -> case readTuple readInt (readList' readInt') d1 of
  (Just (i,l),d2) -> case Map.lookup i sl of
   (Just s) -> case listToTypes m l of
     (Just l') -> case tag d2 of
      ((EndElement "TyApp"):d3) -> (Just (Map.insert ((Map.size m)+1) (TyApp s (reverse l')) m),d3)
      _ -> (Nothing,d)
     _ -> (Nothing,d)
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 ((StartElement "TyVar" _):d1) -> case readInt d1 of
  (Just i,d2) -> case Map.lookup i sl of
   (Just s) -> case tag d2 of
    ((EndElement "TyVar"):d3) -> (Just (Map.insert ((Map.size m)+1) (TyVar s) m),d3)
    _ -> (Nothing,d)
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 _ -> (Nothing,d)


readParseType :: SaxEvL -> (Maybe HolParseType,SaxEvL)
readParseType d = case tag d of
 ((StartElement "Prefix" _):d1) -> case tag d1 of
  ((EndElement "Prefix"):d2) -> (Just Prefix,d2)
  _ -> (Nothing,d)
 ((StartElement "InfixR" _):d1) -> case readInt d1 of
  (Just i,d2) -> case tag d2 of
   ((EndElement "InfixR"):d3) -> (Just (InfixR i),d3)
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 ((StartElement "InfixL" _):d1) -> case readInt d1 of
  (Just i,d2) -> case tag d2 of
   ((EndElement "InfixL"):d3) -> (Just (InfixL i),d3)
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 ((StartElement "Normal" _):d1) -> case tag d1 of
  ((EndElement "Normal"):d2) -> (Just Normal,d2)
  _ -> (Nothing,d)
 ((StartElement "Binder" _):d1) -> case tag d1 of
  ((EndElement "Binder"):d2) -> (Just Binder,d2)
  _ -> (Nothing,d)
 _ -> (Nothing,d)


readTermInfo :: SaxEvL -> (Maybe HolTermInfo,SaxEvL)
readTermInfo d = case readParseType d of
 (Just p,d1) -> case readTuple readWord readParseType d1 of
  (Just (s,p1),d2) -> (Just (HolTermInfo (p, Just (s,p1))),d2)
  _ -> (Just (HolTermInfo (p,Nothing)),d1)
 _ -> (Nothing,d)

readSharedHolTerm :: Map.Map Int HolType -> Map.Map Int String -> SaxEvL -> Map.Map Int Term -> (Maybe (Map.Map Int Term),SaxEvL)
readSharedHolTerm ts sl d m = case tag d of
 ((StartElement "Var" _):d1) -> case readTuple readInt readInt d1 of
  (Just (n,t),d2) -> case readTermInfo d2 of
   (Just ti,d3) -> case Map.lookup n sl of
    (Just name) -> case Map.lookup t ts of
     (Just tp) -> case tag d3 of
      ((EndElement "Var"):d4) -> (Just (Map.insert ((Map.size m)+1) (Var name tp ti) m),d4)
      _ -> (Nothing,d)
     _ -> (Nothing,d)
    _ -> (Nothing,d)
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 ((StartElement "Const" _):d1) -> case readTuple readInt readInt d1 of
  (Just (n,t),d2) -> case readTermInfo d2 of
   (Just ti,d3) -> case Map.lookup n sl of
    (Just name) -> case Map.lookup t ts of
     (Just tp) -> case tag d3 of
      ((EndElement "Const"):d4) -> (Just (Map.insert ((Map.size m)+1) (Const name tp ti) m),d4)
      _ -> (Nothing,d)
     _ -> (Nothing,d)
    _ -> (Nothing,d)
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 ((StartElement "Comb" _):d1) -> case readTuple readInt readInt d1 of
  (Just (t1,t2),d2) -> case (Map.lookup t1 m,Map.lookup t2 m) of
   (Just t1',Just t2') -> case tag d2 of
    ((EndElement "Comb"):d3) -> (Just (Map.insert ((Map.size m)+1) (Comb t1' t2') m),d3)
    _ -> (Nothing,d)
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 ((StartElement "Abs" _):d1) -> case readTuple readInt readInt d1 of
  (Just (t1,t2),d2) -> case (Map.lookup t1 m,Map.lookup t2 m) of
   (Just t1',Just t2') -> case tag d2 of
    ((EndElement "Abs"):d3) -> (Just (Map.insert ((Map.size m)+1) (Abs t1' t2') m),d3)
    _ -> (Nothing,d)
   _ -> (Nothing,d)
  _ -> (Nothing,d)
 _ -> (Nothing,d)

importData :: HetcatsOpts -> FilePath -> IO ([(String,[(String,Term)])],[(String,String)])
importData opts fp' = do
    fp <- canonicalizePath fp'
    default_tool_path <- canonicalizePath "./HolLight/OcamlTools/"
    tool_path <- getEnvDef "HETS_HOLLIGHT_TOOLS" default_tool_path
    temp_path <- getTempFile "" (takeBaseName fp)
    h <- SP.runCommand ("ocaml " ++ (show (tool_path </> "export.ml")) ++ " " ++ (show fp) ++ " " ++ (show temp_path))
    c <- SP.waitForProcess h
    s <- L.readFile temp_path
    removeFile temp_path
    let e = ([],[])
    case tag (parsexml s) of
      ((StartElement "HolExport" _):d) -> case readL readStr "Strings" d of
       (Just sl,d1) ->
        let strings = Map.fromList (zip [1..] sl)
          in case foldS (readSharedHolType strings) Map.empty "SharedHolTypes" d1 of
           (Just hol_types,d2) -> case foldS (readSharedHolTerm hol_types strings) Map.empty "SharedHolTerms" d2 of
            (Just hol_terms,d3) -> case readL (readTuple readWord (readList' (readTuple readWord (readMappedInt hol_terms)))) "Libs" d3 of
             (Just libs,d4) -> case readL (readTuple readWord readWord) "LibLinks" d4 of
              (Just liblinks,_) -> return (libs,liblinks)
              _ -> return e
             _ -> return e
            _ -> return e
           _ -> return e
       _ -> return e
      _ -> return e

get_types :: Map.Map String Int -> HolType -> Map.Map String Int
get_types m t = case t of
 (TyVar _) -> m
 (TyApp s ts) -> let m' = foldl get_types m ts in
                     Map.insert s (length ts) m'

mergeTypesOps :: (Map.Map String Int,Map.Map String HolType)
                 -> (Map.Map String Int,Map.Map String HolType)
                 -> (Map.Map String Int,Map.Map String HolType)
mergeTypesOps (ts1,ops1) (ts2,ops2) =
 (Map.union ts1 ts2,Map.union ops1 ops2)

get_ops :: Term
           -> (Map.Map String Int,Map.Map String HolType)
get_ops tm = case tm of
 (Var _ t _)    -> let ts = get_types Map.empty t
                     in (ts,Map.empty)
 (Const s t _)  -> let ts = get_types Map.empty t
                     in (ts,Map.insert s t Map.empty)
 (Comb t1 t2) -> mergeTypesOps
                  (get_ops t1)
                  (get_ops t2)
 (Abs t1 t2)  -> mergeTypesOps
                  (get_ops t1)
                  (get_ops t2)

calcSig :: [(String,Term)] -> Sign
calcSig tm = let (ts,os) = foldl
                      (\p (_,t) -> (mergeTypesOps (get_ops t) p))
                      (Map.empty,Map.empty) tm
                 in Sign {
                   types = ts
                  ,ops = os }

sigDepends :: Sign -> Sign -> Bool
sigDepends s1 s2 = ((Map.size (Map.intersection (types s1) (types s2))) /= 0) ||
                   ((Map.size (Map.intersection (ops s1) (ops s2))) /= 0)

prettifyTypeVarsTp :: HolType -> Map.Map String String -> (HolType,Map.Map String String)
prettifyTypeVarsTp (TyVar s)    m = case Map.lookup s m of
                                    Just s' -> (TyVar s',m)
                                    Nothing -> let s' = '\'':(names!!(Map.size m))
                                               in (TyVar s',Map.insert s s' m)
prettifyTypeVarsTp (TyApp s ts) m = let (ts',m') =
                                              foldl (\(ts'',m'') t -> 
                                                let (t',m''') = prettifyTypeVarsTp t m''
                                                in (t':ts'',m''')
                                               ) ([],m) ts
                                   in (TyApp s ts',m')

prettifyTypeVarsTm :: Term -> Map.Map String String -> (Term,Map.Map String String)
prettifyTypeVarsTm (Const s t p) _ =
 let (t1,m1) = prettifyTypeVarsTp t Map.empty
 in (Const s t1 p,m1)
prettifyTypeVarsTm (Comb tm1 tm2) m =
 let (tm1',m1) = prettifyTypeVarsTm tm1 m
     (tm2',m2) = prettifyTypeVarsTm tm2 m1
 in (Comb tm1' tm2',m2)
prettifyTypeVarsTm (Abs tm1 tm2) m =
 let (tm1',m1) = prettifyTypeVarsTm tm1 m
     (tm2',m2) = prettifyTypeVarsTm tm2 m1
 in (Abs tm1' tm2',m2)
prettifyTypeVarsTm t m = (t,m)

prettifyTypeVars :: ([(String,[(String,Term)])],[(String,String)]) -> 
                    ([(String,[(String,Term)])],[(String,String)])
prettifyTypeVars (libs,lnks) =
 let libs' = map (\(s,terms) ->
      let terms' = foldl (\tms (ts,t) ->
            let (t',_) = prettifyTypeVarsTm t Map.empty
            in ((ts,t'):tms))
             [] terms
      in (s,terms')
      ) libs
 in (libs',lnks)

treeLevels :: [(String,String)] -> Map.Map Int [(String,String)]
treeLevels l = let lk = foldr (\(imp,t) l' -> case lookup t l' of
                                 Just (p,_) -> (imp,(p+1,t)):l'
                                 Nothing -> (imp,(1,t)):(t,(0,"")):l') [] l
                        in foldl (\m (imp,(p,t)) ->
                            let s = Map.findWithDefault [] p m
                                in Map.insert p ((imp,t):s) m) Map.empty lk

makeNamedSentence :: String -> Term -> Named Sentence
makeNamedSentence n t = makeNamed n $ Sentence { term = t, proof = Nothing }

_insNodeDG :: Sign -> [Named Sentence] -> String -> (DGraph, Map.Map String (String,Data.Graph.Inductive.Graph.Node,DGNodeLab)) -> (DGraph, Map.Map String (String,Data.Graph.Inductive.Graph.Node,DGNodeLab))
_insNodeDG sig sens n (dg,m) = let gt = G_theory HolLight (makeExtSign HolLight sig) startSigId
                                          (toThSens sens) startThId
                                   n' = snd (System.FilePath.Posix.splitFileName n)
                                   labelK = newInfoNodeLab
                                          (makeName (mkSimpleId n'))
                                          (newNodeInfo DGEmpty)
                                          gt
                                   k = getNewNodeDG dg
                                   m' = Map.insert n (n,k,labelK) m
                                   insN = [InsertNode (k,labelK)]
                                   newDG = changesDGH dg insN
                                   labCh = [SetNodeLab labelK (k, labelK
                                         { globalTheory = computeLabelTheory Map.empty newDG
                                           (k, labelK) })]
                                   newDG1 = changesDGH newDG labCh in (newDG1,m')

anaHolLightFile :: HetcatsOpts -> FilePath -> IO (Maybe (LibName, LibEnv))
anaHolLightFile opts path = do
   (libs_, lnks_) <- importData opts path
   let (libs,lnks) = prettifyTypeVars ((libs_, lnks_))
   let h = treeLevels lnks
   let fixLinks m l = case l of
        (l1:l2:l') -> if ((snd l1) == (snd l2)) && (sigDepends
                          (Map.findWithDefault emptySig (fst l1) m)
                          (Map.findWithDefault emptySig (fst l2) m)) then
                       ((fst l1,fst l2):(fixLinks m (l2:l')))
                      else (l1:l2:(fixLinks m l'))
        l' -> l'
   let uniteSigs m lnks' = foldl (\m' (s,t) -> case resultToMaybe (sigUnion
                                                                   (Map.findWithDefault emptySig s m')
                                                                   (Map.findWithDefault emptySig t m')) of
                                                Nothing      -> m'
                                                Just new_tsig -> Map.insert t new_tsig m') m lnks'
   let m = foldl (\m' (s,l) -> Map.insert s (calcSig l) m') Map.empty libs
   let (m',lnks') = foldr (\lvl (m'',lnks_loc) -> let lvl' = Map.findWithDefault [] lvl h
                                                      lnks_next = fixLinks m'' (reverse lvl')
{- we'd probably need to take care of dependencies on previously imported files not imported by the file imported last -}
                                               in (uniteSigs m'' lnks_next,lnks_next++lnks_loc)
                    ) (m,[]) [0..((Map.size h)-1)]
   let (dg',node_m) = foldr (\(lname,lterms) (dg,node_m') ->
           let sig = Map.findWithDefault emptySig lname m'
               sens = map (\(n,t) -> makeNamedSentence n t) lterms in
           _insNodeDG sig sens lname (dg,node_m')) (emptyDG,Map.empty) libs
       dg'' = foldr (\(source,target) dg -> case Map.lookup source node_m of
                                           Just (n,k,lk) -> case Map.lookup target node_m of
                                             Just (n1,k1,lk1) -> let sig  = Map.findWithDefault emptySig n  m'
                                                                     sig1 = Map.findWithDefault emptySig n1 m' in
                                                          case resultToMaybe $ subsig_inclusion HolLight sig sig1 of
                                                            Nothing -> dg
                                                            Just incl ->
                                                              let inclM = gEmbed $ mkG_morphism HolLight incl
                                                                  insE = [InsertEdge (k, k1,globDefLink inclM DGLinkImports)]
                                                                  newDG = changesDGH dg insE
                                                                  updL = [SetNodeLab lk1 (k1, lk1
                                                                          { globalTheory = computeLabelTheory Map.empty newDG
                                                                           (k1, lk1) }),
                                                                          SetNodeLab lk (k, lk
                                                                          { globalTheory = computeLabelTheory Map.empty newDG
                                                                           (k, lk) })]
                                                              in changesDGH newDG updL
                                             Nothing -> dg
                                           Nothing -> dg) dg' lnks'
       le = Map.insert (emptyLibName (System.FilePath.Posix.takeBaseName path)) dg'' (Map.empty)
   return (Just (emptyLibName (System.FilePath.Posix.takeBaseName path), le))
