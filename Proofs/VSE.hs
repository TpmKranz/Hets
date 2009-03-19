{-# OPTIONS -cpp #-}
{- |
Module      :  $Header$
Description :  Interface to send structured theories to the VSE prover
Copyright   :  (c) C. Maeder, DFKI 2009
License     :  similar to LGPL, see HetCATS/LICENSE.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  needs POSIX

call an adaption of VSE II to hets

the prover should be attached to a node's menu (if applicable) but take the
whole library environment as in- and output like development graph rules.
-}

module Proofs.VSE where

import Static.GTheory
import Static.DevGraph
import Static.PrintDevGraph
import Static.DGTranslation

import Proofs.QualifyNames
import Proofs.EdgeUtils

import Common.AS_Annotation
import Common.ExtSign
import Common.Id
import Common.LibName
import Common.Result
import Common.ResultT
import Common.SExpr
import qualified Common.OrderedMap as OMap

import Logic.Logic
import Logic.Prover
import Logic.Comorphism
import Logic.Coerce
import Logic.Grothendieck

import VSE.Logic_VSE

import VSE.Prove
import VSE.ToSExpr
import Comorphisms.CASL2VSE
import CASL.ToSExpr
import CASL.Logic_CASL

import Data.Char
import Data.Maybe
import qualified Data.Map as Map
import qualified Data.Set as Set
import Data.Graph.Inductive.Basic (elfilter, gfold)
import Data.Graph.Inductive.Graph hiding (out)

import Control.Monad.Trans

thName :: LIB_NAME -> LNode DGNodeLab -> String
thName ln (n, lbl) = map (\ c -> if elem c "/,[]: " then '-' else c)
           $ shows (getLIB_ID ln) "_" ++ getDGNodeName lbl ++ "_" ++ show n

getSubGraph :: Node -> DGraph -> DGraph
getSubGraph n dg =
    let g = dgBody dg
        ns = nodes g
        sns = gfold pre' (\ c s -> Set.insert (node' c) s)
          (\ m s -> Set.union s $ fromMaybe Set.empty m, Set.empty) [n] g
    in foldr delNodeDG dg $ Set.toList $ Set.difference (Set.fromList ns) sns

-- | applies basic inference to a given node and whole import tree above
prove :: [AnyComorphism] -> (LIB_NAME, Node) -> LibEnv
      -> IO (Result (LibEnv, Result G_theory))
prove _cms (ln, node) libEnv =
  runResultT $ do
    qLibEnv <- liftR $ qualifyLibEnv libEnv
    let dg1 = lookupDGraph ln qLibEnv
        dg2 = dg1 { dgBody = elfilter (isGlobalEdge . dgl_type) $ dgBody dg1 }
        dg3 = getSubGraph node dg2
        oLbl = labDG dg3 node
        ostr = thName ln (node, oLbl)
    G_theory olid _ _ _ _ <- return $ dgn_theory oLbl
    let mcm = if Logic CASL == Logic olid then Just (Comorphism CASL2VSE) else
             Nothing
    dGraph <- liftR $ maybe return (flip dg_translation) mcm dg3
    let nls = topsortedNodes dGraph
        ns = map snd nls
    ts <- liftR $ mapM
      (\ lbl -> do
         let lbln = getDGNodeName lbl
         G_theory lid (ExtSign sign0 _) _ sens0 _ <- return $ dgn_theory lbl
         (sign1, sens1) <-
           addErrorDiag "failure when proving VSE nodes of" (getLIB_ID ln)
           $ coerceBasicTheory lid VSE
             ("cannot cast untranslated node '" ++ lbln ++ "'")
             (sign0, toNamedList sens0)
         let (sign2, sens2) = addUniformRestr sign1 sens1
         return
           ( show $ prettySExpr
             $ qualVseSignToSExpr (mkSimpleId lbln)
               (getLIB_ID ln) sign2
           , show $ prettySExpr
             $ SList $ map (namedSenToSExpr sign2) sens2)) ns
    nLibEnv <- lift $ do
#ifdef TAR_PACKAGE
       moveVSEFiles ostr
#endif
       (inp, out, cp) <- prepareAndCallVSE
       sendMyMsg inp $ "(" ++ unlines (map (thName ln) nls) ++ ")"
       mapM_ (\ nl -> do
           readMyMsg cp out linksP
           sendMyMsg inp $ getLinksTo ln dGraph nl) nls
       mapM_ (\ (fsig, _) -> do
           readMyMsg cp out sigP
           sendMyMsg inp fsig) ts
       mapM_ (\ (_, sens) -> do
           readMyMsg cp out lemsP
           sendMyMsg inp sens) ts
       ms <- readFinalVSEOutput cp out
#ifdef TAR_PACKAGE
       createVSETarFile ostr
#endif
       case ms of
         Nothing -> return libEnv
         Just lemMap -> return $ foldr (\ (n, lbl) le ->
                 let str = map toUpper $ thName ln (n, lbl)
                     lems = Set.fromList $ Map.findWithDefault [] str lemMap
                 in if Set.null lems then le else let
                     dg = lookupDGraph ln le
                     in case lab (dgBody dg) n of
                     Nothing -> le -- node missing in original graph
                     Just olbl -> case dgn_theory olbl of
                       G_theory lid sig sigId sens _ -> let
                         axs = Map.keys $ OMap.filter isAxiom sens
                         nsens = OMap.mapWithKey (\ name sen ->
                             if not (isAxiom sen) && Set.member
                                  (map toUpper $ transString name) lems
                             then sen {
                                 senAttr = ThmStatus $
                                     (Comorphism CASL2VSE,
                                     BasicProof VSE $
                                       mkVseProofStatus name axs)
                                       : thmStatus sen }
                             else sen) sens
                         ndg = changeDGH dg $ SetNodeLab olbl
                               (n, olbl { dgn_theory =
                                 G_theory lid sig sigId nsens startThId })
                        in Map.insert ln ndg le) libEnv nls
    return (nLibEnv, Result [] Nothing)

getLinksTo :: LIB_NAME -> DGraph -> LNode DGNodeLab -> String
getLinksTo ln dg (n, lbl) = show $ prettySExpr $ SList
  $ map (\ (s, _, el) -> let
    ltype = dgl_type el
    defl = isGlobalDef ltype
    in SList $
    [ SSymbol $ (if defl then "definition" else "theorem") ++ "-link"
    , SSymbol $ filter (not . isSpace) $ showEdgeId $ dgl_id el
    , SSymbol $ thName ln (s, labDG dg s)
    , SSymbol $ thName ln (n, lbl)
    , SSymbol "global"
    , SList $ SSymbol "morphism" : hetMorToSSexpr (dgl_morphism el)]
    ++ if defl then [] else
       [SSymbol $ if isProven ltype then "proven" else "open"])
  $ filter (\ (s, _, _) -> s /= n) $ innDG dg n

hetMorToSSexpr :: GMorphism -> [SExpr]
hetMorToSSexpr (GMorphism cid _ _ mor _) =
  let tlid = targetLogic cid
  in case coerceMorphism tlid VSE "" mor of
       Just vsemor -> morToSExprs vsemor
       Nothing -> case coerceMorphism tlid CASL "" mor of
         Just cmor -> morToSExprs cmor
         Nothing -> []
