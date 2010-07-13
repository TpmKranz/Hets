{- |
Module      :  $Header$
Description :  apply xupdate changes to a development graph
Copyright   :  (c) Christian Maeder, DFKI GmbH 2010
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt
Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  non-portable(Grothendieck)

adjust development graph according to xupdate information
-}

module Static.ApplyChanges where

import Static.DevGraph
import Static.History

import Data.Graph.Inductive.Graph as Graph

import Static.FromXml

lookupNodeByNodeName :: NodeName -> DGraph -> [LNode DGNodeLab]
lookupNodeByNodeName nn = lookupNodeWith ((== nn) . dgn_name . snd)

remove :: Monad m => SelElem -> DGraph -> m DGraph
remove se dg = let err = "Static.ApplyChanges.remove: " in case se of
  NodeElem nn m -> case m of
    Nothing -> let s = showName nn in case lookupNodeByNodeName nn dg of
      [i] -> return $ changeDGH dg (DeleteNode i)
      [] -> fail $ err ++ "node not found: " ++ s
      _ -> fail $ err ++ "ambiguous node: " ++ s
    Just _ -> fail $ err ++ "cannot remove node symbols"
  LinkElem eId src tar m -> let e = showEdgeId eId in case m of
    Nothing ->
      case (lookupNodeByNodeName src dg, lookupNodeByNodeName tar dg) of
      ([s], [t]) -> case filter (\ (_, o, l) -> o == fst t && eId == dgl_id l)
        $ outDG dg (fst s) of
        [le] -> return $ changeDGH dg (DeleteEdge le)
        [] -> fail $ err ++ "edge not found: " ++ e
        _ -> fail $ err ++ "ambiguous edge: " ++ e
      _ -> fail $ err ++ "non-unique source or target for edge: " ++ e
    Just _ -> fail $ err ++ "cannot remove edge morphisms"
  _ -> fail $ err ++ "unimplemented selection"