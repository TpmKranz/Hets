{- |
Module      :  $Header$
Description :  Functions used by 'Comorphisms.CASL2SPASS' and 'SPASS.Prove'
               for the translation into valid SPASS identifiers
Copyright   :  (c) Klaus L�ttich, Uni Bremen 2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luettich@tzi.de
Stability   :  provisional
Portability :  portable

collection of functions used by Comorphisms.CASL2SPASS and SPASS.Prove
 for the translation of CASL identifiers and axiom labels into
 valid SPASS identifiers
-}

module SPASS.Translate (reservedWords, transId, transSenName) where

import Data.Char

import Common.Id
import Common.DocUtils
import qualified Data.Set as Set
import qualified Data.Map as Map

import SPASS.Sign
import SPASS.Print ()
import SPASS.Utils

import Common.ProofUtils

-- | collect all keywords of SPASS
reservedWords :: Set.Set SPIdentifier
reservedWords = Set.fromList (map ((flip showDoc) "") [SPEqual
                                          , SPTrue
                                          , SPFalse
                                          , SPOr
                                          , SPAnd
                                          , SPNot
                                          , SPImplies
                                          , SPImplied
                                          , SPEquiv] ++
 -- this list of reserved words has bin generated with:
 -- perl HetCATS/utils/transformLexerFile.pl spass-3.0c/dfgscanner.l
   words
     ("and author axioms begin_problem by box all clause cnf comp "++
      "conjectures conv date description dia some div dnf domain "++
      "domrestr eml EML DL end_of_list end_problem equal equiv "++
      "exists false forall formula freely functions generated "++
      "hypothesis id implied implies list_of_clauses list_of_declarations "++
      "list_of_descriptions list_of_formulae list_of_general_settings "++
      "list_of_proof list_of_settings list_of_special_formulae "++
      "list_of_symbols list_of_terms logic name not operators "++
      "or prop_formula concept_formula predicate predicates quantifiers "++
      "ranrestr range rel_formula role_formula satisfiable set_DomPred "++
      "set_flag set_precedence set_ClauseFormulaRelation set_selection "++
      "sort sorts status step subsort sum test translpairs true "++
      "unknown unsatisfiable version static"
     ))

transSenName :: String -> String
transSenName = transId CSort . simpleIdToId . mkSimpleId


transId :: CType -> Id -> SPIdentifier
transId t iden
    | checkIdentifier t str =
                            if Set.member str reservedWords
                            then changeFirstChar $ "X_"++str
                            else str
    | otherwise = changeFirstChar $
                  concatMap transToSPChar $
                  addChar str
    where str = changeFirstChar $ substDigits $ show iden
          addChar s =
              case s of
              "" -> error "SPASS.Translate.transId: empty string not allowed"
              ('_':_) -> case t of
                         COp _ -> 'o':s
                         CPred _ -> 'p':s
                         _ -> error $ "SPASS.Translate.transId: Variables "++
                                      "and Sorts don't start with '_'"
              _ -> s
          changeFirstChar s =
              case s of
              "" -> error $ "SPASS.Translate.transId: each identifier "++
                            "must be non empty here"
              (x:xs) -> toValidChar x : xs
          toValidChar =
              case t of
              CVar _ -> toUpper
              _ -> toLower

charMap_SP :: Map.Map Char String
charMap_SP = Map.union
             (Map.fromList [('\'',"Prime")
                           ,(' ',"_")
                           ,('\n',"_")])
             charMap

transToSPChar :: Char -> SPIdentifier
transToSPChar c
    | checkSPChar c = [c]
    | otherwise = Map.findWithDefault def c charMap_SP
    where def = "Slash_"++ show (ord c)

substDigits :: String -> String
substDigits = concatMap subst
    where subst c
              | isDigit c = case c of
                '0' -> "zero"
                '1' -> "one"
                '2' -> "two"
                '3' -> "three"
                '4' -> "four"
                '5' -> "five"
                '6' -> "six"
                '7' -> "seven"
                '8' -> "eight"
                '9' -> "nine"
                _ -> error ("SPASS.Translate.substDigits: unknown digit: \'"
                            ++c:"\'")
              | otherwise = [c]
