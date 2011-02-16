{-# LANGUAGE MultiParamTypeClasses, TypeSynonymInstances #-}
{- |
Module      :  $Header$
Description :  Instances of classes defined in Logic.hs for the Edinburgh
               Logical Framework
Copyright   :  (c) Kristina Sojakova, DFKI Bremen 2009
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  k.sojakova@jacobs-university.de
Stability   :  experimental
Portability :  portable
-}

module LF.Logic_LF where

import LF.AS
import LF.Parse
import LF.Sign
import LF.Morphism
import LF.ATC_LF ()
import LF.Analysis
import LF.Framework

import Logic.Logic

import Common.Result
import Common.ExtSign

import qualified Data.Map as Map

data LF = LF deriving Show

instance Language LF where
   description LF = "Edinburgh Logical Framework"

instance Category Sign Morphism where
   ide = idMorph
   dom = source
   cod = target
   composeMorphisms = compMorph
   isInclusion = Map.null . symMap . canForm
   legal_mor = const True

instance Syntax LF BASIC_SPEC SYMB_ITEMS SYMB_MAP_ITEMS where
   parse_basic_spec LF = Just basicSpec
   parse_symb_items LF = Just symbItems
   parse_symb_map_items LF = Just symbMapItems

instance Sentences LF
   Sentence
   Sign
   Morphism
   Symbol
   where
   map_sen LF m = (Result []) . (translate m)
   sym_of LF = singletonList . getSymbols

instance Logic LF
   ()
   BASIC_SPEC
   Sentence
   SYMB_ITEMS
   SYMB_MAP_ITEMS
   Sign
   Morphism
   Symbol
   RAW_SYM
   ()

instance StaticAnalysis LF
   BASIC_SPEC
   Sentence
   SYMB_ITEMS
   SYMB_MAP_ITEMS
   Sign
   Morphism
   Symbol
   RAW_SYM
   where
   basic_analysis LF = Just $ basicAnalysis
   stat_symb_items LF = symbAnalysis
   stat_symb_map_items LF = symbMapAnalysis
   symbol_to_raw LF = symName
   matches LF s1 s2 =
     if (isSym s2)
        then symName s1 == s2         --symbols are matched by their name
        else True   -- expressions are checked manually hence always True
   empty_signature LF = emptySig
   is_subsig LF = isSubsig
   subsig_inclusion LF = inclusionMorph
   signature_union LF = sigUnion
   intersection LF = sigIntersection
   generated_sign LF syms sig = do
     sig'<- genSig syms sig
     inclusionMorph sig' sig
   cogenerated_sign LF syms sig = do
     sig'<- coGenSig syms sig
     inclusionMorph sig' sig
   induced_from_to_morphism LF m (ExtSign sig1 _) (ExtSign sig2 _) =
     inducedFromToMorphism (translMapAnalysis m sig1 sig2) sig1 sig2
   induced_from_morphism LF m sig =
     inducedFromMorphism (renamMapAnalysis m sig) sig   

instance LogicFram LF
   ()
   BASIC_SPEC
   Sentence
   SYMB_ITEMS
   SYMB_MAP_ITEMS
   Sign
   Morphism
   Symbol
   RAW_SYM
   ()
   where
   base_sig LF = baseSig
   write_logic LF = writeLogic
   write_syntax LF = writeSyntax
