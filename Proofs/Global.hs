{- |
Module      :  $Header$
Description :  global proof rules for development graphs
Copyright   :  (c) Jorina F. Gerken, Till Mossakowski, Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  ken@informatik.uni-bremen.de
Stability   :  provisional
Portability :  non-portable(DevGraph)

global proof rules for development graphs.
   Follows Sect. IV:4.4 of the CASL Reference Manual.
-}

module Proofs.Global
    ( globSubsume
    , globDecomp
    , globDecompAux -- for Test.hs
    , globDecompFromList
    , globSubsumeFromList
    ) where

import Data.Graph.Inductive.Graph
import qualified Data.Map as Map

import Static.GTheory
import Static.DevGraph

import Common.LibName
import Common.Utils

import Proofs.EdgeUtils
import Proofs.StatusUtils

globDecompRule :: LEdge DGLinkLab -> DGRule
globDecompRule = DGRuleWithEdge "Global-Decomposition"

{- apply rule GlobDecomp to all global theorem links in the current DG
   current DG = DGm
   add to proof status the pair ([GlobDecomp e1,...,GlobDecomp en],DGm+1)
   where e1...en are the global theorem links in DGm
   DGm+1 results from DGm by application of GlobDecomp e1,...,GlobDecomp en -}


{- | applies global decomposition to the list of edges given (global
     theorem edges) if possible, if empty list is given then to all
     unproven global theorems.
     Notice: (for ticket 5, which solves the problem across library border)
     1. before the actual global decomposition is applied, the whole DGraph is
     updated firstly by calling the function updateDGraph.
     2. The changes of the update action should be added as the head of the
     history.
-}
globDecompFromList :: LibName -> [LEdge DGLinkLab] -> LibEnv -> LibEnv
globDecompFromList ln globalThmEdges proofStatus =
    let dgraph = lookupDGraph ln proofStatus
        finalGlobalThmEdges = filter (liftE isUnprovenGlobalThm) globalThmEdges
        auxGraph = foldl (updateDGraph proofStatus) dgraph
           $ nubOrd $ map (\ (src, _, _) -> src) finalGlobalThmEdges
        newDGraph = foldl globDecompAux auxGraph finalGlobalThmEdges
    in Map.insert ln newDGraph proofStatus

{- | update the given DGraph with source nodes of all global unproven
     links.
     The idea is, to expand the given DGraph by adding all the referenced
     nodes related to the given source nodes in other libraries and the
     corresponding links as well.
     If a certain node is a referenced node and not expanded yet, then its
     parents will be found by calling getRefParents.
     These parents will be added into current DGraph using updateDGraphAux
-}
updateDGraph :: LibEnv -> DGraph
             -> Node -- source nodes of all global unproven links
             -> DGraph
updateDGraph le dg x =
    {- checks if it is an unexpanded referenced node
       the function lookupInRefNodesDG only checks the
       nodes which are not expanded. -}
    case lookupInRefNodesDG x dg of
         Just (refl, refn) ->
            let
            parents = getRefParents le refl refn
            {- important for those, who's doing redo/undo function:
               notice that if the node is expanded, then it should be
               deleted out of the unexpanded map using
               deleteFromRefNodesDG -}
            auxDG = foldl (updateDGraphAux le x refl)
                dg parents
            in auxDG
         _ -> dg

{- | get all the parents, namely the related referenced nodes and the links
     between them and the present to be expanded node.
-}
getRefParents :: LibEnv -> LibName
              -> Node -- the present to be expanded node
              -> [(LNode DGNodeLab, [DGLinkLab])]
getRefParents le refl refn =
   let
   {- get the previous objects to the current one -}
   dg = lookupDGraph refl le
   pres = innDG dg refn
   in modifyPs dg pres

{- | modify the parents to a better form.
     e.g. if the list is like:
     [(a, 1), (b, 1), (c, 2), (d, 2), (e, 2)]
     which means that node 1 is related via links a and b, and node 2 is
     related via links c, d and e.
     then to advoid too many checking by inserting, we can modify the list
     above to a form like this:
     [(1, [a, b]), (2, [c, d, e])]
     which simplifies the inserting afterwards ;)
-}
modifyPs :: DGraph -> [LEdge DGLinkLab] -> [(LNode DGNodeLab, [DGLinkLab])]
modifyPs dg ls =
   map
   (\ (n, x) -> ((n, labDG dg n), x))
   $ modifyPsAux ls
   where
   modifyPsAux :: Ord a => [(a, t, b)] -> [(a, [b])]
   modifyPsAux l =
        Map.toList $ Map.fromListWith (++) [(k, [v]) | (k, _, v) <- l ]

{- | the actual update function to insert a list of related parents to the
     present to be expanded node.
     It inserts the related referenced node firstly by calling addParentNode.
     Then it inserts the related links by calling addParentLinks
     Notice that nodes have to be added firstly, so that the links can be
     connected to the inserted nodes ;), especially by adding to the change
     list.
-}
updateDGraphAux :: LibEnv -> Node -- the present to be expanded node
                -> LibName -> DGraph -> (LNode DGNodeLab, [DGLinkLab])
                -> DGraph
updateDGraphAux libenv n refl dg (pnl, pls) =
   let
   (auxDG, newN) = addParentNode libenv dg refl pnl
   in addParentLinks auxDG newN n pls

{- | add the given parent node into the current dgraph
-}
addParentNode :: LibEnv -> DGraph ->  LibName
              -> LNode DGNodeLab -- the referenced parent node
              -> (DGraph, Node)
addParentNode libenv dg refl (refn, oldNodelab) =
   let
   {-
     To advoid the chain which is desribed in ticket 5, the parent node should
     be a non referenced node firstly, so that the actual parent node can be
     related.
   -}
   (nodelab, newRefl, newRefn) = if isDGRef oldNodelab then
                let
                tempRefl = dgn_libname oldNodelab
                tempRefn = dgn_node oldNodelab
                originDG = lookupDGraph tempRefl libenv
                in
                (labDG originDG tempRefn, tempRefl, tempRefn)
             else (oldNodelab, refl, refn)
   {-
     Set the sgMap and tMap too.
     Notice for those who are doing undo/redo, because the DGraph is actually
     changed if the maps are changed ;)
   -}
   -- creates an empty GTh, please check the definition of this function
   -- because there can be some problem or errors at this place.
   newGTh = case dgn_theory nodelab of
     G_theory lid sig ind _ _ -> noSensGTheory lid sig ind
   refInfo = newRefInfo newRefl newRefn
   newRefNode = (newInfoNodeLab (dgn_name nodelab) refInfo newGTh)
     { globalTheory = globalTheory nodelab }
   in
   -- checks if this node exists in the current dg, if so, nothing needs to be
   -- done.
   case lookupInAllRefNodesDG refInfo dg of
        Nothing -> let newN = getNewNodeDG dg in
           ( changeDGH (addToRefNodesDG newN refInfo dg)
             $ InsertNode (newN, newRefNode)
           , newN)
        Just extN -> (dg, extN)

{- | add a list of links between the given two node ids.
-}
addParentLinks :: DGraph -> Node -> Node -> [DGLinkLab] -> DGraph
addParentLinks dg src tgt ls =
  let oldLinks = map (\ (_, _, l) -> l)
        $ filter (\ (s, _, _) -> s == src) $ innDG dg tgt
      newLinks = map (\ l -> l
                         { dgl_id = defaultEdgeId
                         , dgl_type = invalidateProof $ dgl_type l }) ls
  in if null oldLinks then
         changesDGH dg $ map (\ l -> InsertEdge (src, tgt, l)) newLinks
     else dg -- assume ingoing links are already properly set

{- applies global decomposition to all unproven global theorem edges
   if possible -}
globDecomp :: LibName -> LibEnv -> LibEnv
globDecomp ln proofStatus =
    let dgraph = lookupDGraph ln proofStatus
        globalThmEdges = labEdgesDG dgraph
    in
    globDecompFromList ln globalThmEdges proofStatus

{- auxiliary function for globDecomp (above)
   actual implementation -}
globDecompAux :: DGraph -> LEdge DGLinkLab -> DGraph
globDecompAux dgraph edge =
  let newDGraph = globDecompForOneEdge dgraph edge
  in groupHistory dgraph (globDecompRule edge) newDGraph

-- applies global decomposition to a single edge
globDecompForOneEdge :: DGraph -> LEdge DGLinkLab -> DGraph
globDecompForOneEdge dgraph edge@(source, target, edgeLab) = let
    defEdgesToSource = filter (liftE isDefEdge) $ innDG dgraph source
    paths = [edge] : map (: [edge]) defEdgesToSource
    (newGr, proof_basis) = foldl
      (globDecompForOneEdgeAux target) (dgraph, emptyProofBasis) paths
    provenEdge = (source, target, edgeLab
        { dgl_type = setProof (Proven (globDecompRule edge) proof_basis)
            $ dgl_type edgeLab
        , dgl_origin = DGLinkProof })
    in changesDGH newGr [DeleteEdge edge, InsertEdge provenEdge]

{- auxiliary function for globDecompForOneEdge (above)
   actual implementation -}
globDecompForOneEdgeAux :: Node -> (DGraph, ProofBasis)
                        -> [LEdge DGLinkLab]
                        -> (DGraph, ProofBasis)
-- for each path an unproven localThm edge is inserted
globDecompForOneEdgeAux target (dgraph, proof_basis) path =
  case path of
    [] -> error "globDecompForOneEdgeAux"
    (node, _, lbl) : rpath -> let
      lbltype = dgl_type lbl
      isHiding = isHidingDef lbltype
      morphismPath = if isHiding then rpath else path
      morphism = case calculateMorphismOfPath morphismPath of
        Just morph -> morph
        Nothing -> error "globDecomp: could not determine morphism of new edge"
      defEdgesToTarget = filter
        (\ (s, _, l) -> s == node && isGlobalDef (dgl_type l)
        && dgl_morphism l == morphism)
        $ innDG dgraph target
      newEdgeLbl = defDGLink morphism
        (if isHiding then hidingThm $ dgl_morphism lbl
            else if isGlobalDef lbltype then globalThm else localThm)
        DGLinkProof
      newEdge = (node, target, newEdgeLbl)
      in case defEdgesToTarget of
      (_, _, dl) : _ | not isHiding
             -> (dgraph, addEdgeId proof_basis $ dgl_id dl)
      _ | node == target && isInc (getRealDGLinkType newEdgeLbl)
               && isGlobalDef lbltype
             -> (dgraph, addEdgeId proof_basis $ dgl_id lbl)
      _ -> case tryToGetEdge newEdge dgraph of
        Nothing -> let
          newGraph = changeDGH dgraph $ InsertEdge newEdge
          finalEdge = case getLastChange newGraph of
            InsertEdge final_e -> final_e
            _ -> error "Proofs.Global.globDecompForOneEdgeAux"
          in (newGraph, addEdgeId proof_basis $ getEdgeId finalEdge)
        Just e -> (dgraph, addEdgeId proof_basis $ getEdgeId e)

globSubsumeFromList :: LibName -> [LEdge DGLinkLab] -> LibEnv -> LibEnv
globSubsumeFromList ln globalThmEdges libEnv =
    let dgraph = lookupDGraph ln libEnv
        finalGlobalThmEdges = filter (liftE isUnprovenGlobalThm) globalThmEdges
        nextDGraph = foldl
            (globSubsumeAux libEnv) dgraph finalGlobalThmEdges
    in Map.insert ln nextDGraph libEnv

-- | tries to apply global subsumption to all unproven global theorem edges
globSubsume :: LibName -> LibEnv -> LibEnv
globSubsume ln libEnv =
    let dgraph = lookupDGraph ln libEnv
        globalThmEdges = labEdgesDG dgraph
    in globSubsumeFromList ln globalThmEdges libEnv

{- auxiliary function for globSubsume (above) the actual implementation -}
globSubsumeAux :: LibEnv ->  DGraph -> LEdge DGLinkLab  -> DGraph
globSubsumeAux libEnv dgraph ledge@(src, tgt, edgeLab) =
  let morphism = dgl_morphism edgeLab
      filteredPaths = filterPathsByMorphism morphism $ filter (noPath ledge)
                    $ getAllGlobPathsBetween dgraph src tgt
      proofbasis = selectProofBasis dgraph ledge filteredPaths
  in if not (nullProofBasis proofbasis) || isIdentityEdge ledge libEnv dgraph
   then
     let globSubsumeRule = DGRuleWithEdge "Global-Subsumption" ledge
         newEdge = (src, tgt, edgeLab
               { dgl_type = setProof (Proven globSubsumeRule proofbasis)
                   $ dgl_type edgeLab
               , dgl_origin = DGLinkProof })
         newDGraph = changesDGH dgraph [DeleteEdge ledge, InsertEdge newEdge]
     in groupHistory dgraph globSubsumeRule newDGraph
   else dgraph
