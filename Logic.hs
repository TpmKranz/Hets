
-- needs ghc -fglasgow-exts -fallow-overlapping-instances -package data

{- HetCATS/Logic.hs
   $Id$
   Till Mossakowski, Christian Maeder
   
   Provides data structures for logics (with symbols). Logics are
   a type class with an "identitiy" type (usually interpreted
   by a singleton set) which serves to treat logics as 
   data. All the functions in the type class take the
   identity as first argument in order to determine the logic.

   For logic representations see LogicRepr.hs

   References:

   J. A. Goguen and R. M. Burstall
   Institutions: Abstract Model Theory for Specification and
     Programming
   JACM 39, p. 95--146, 1992
   (general notion of logic - model theory only)

   J. Meseguer
   General Logics
   Logic Colloquium 87, p. 275--329, North Holland, 1989
   (general notion of logic - also proof theory;
    notion of logic representation, called map there)

   T. Mossakowski: 
   Specification in an arbitrary institution with symbols
   14th WADT 1999, LNCS 1827, p. 252--270
   (treatment of symbols and raw symbols, see also CASL semantics)

   T. Mossakowski, B. Klin:
   Institution Independent Static Analysis for CASL
   15h WADT 2001, LNCS 2267, p. 221-237, 2002.
   (what is needed for static anaylsis)

   S. Autexier and T. Mossakowski
   Integrating HOLCASL into the Development Graph Manager MAYA
   FroCoS 2002, to appear
   (interface to provers)

   Todo:
   ATerm, XML
   Weak amalgamability
   Metavars
   
-}

module Logic where

import Id
import GlobalAnnotations
import FiniteSet
import FiniteMap
import Graph
import Result
--import Parsec
import Prover -- for one half of class Sentences

import PrettyPrint

-- for coercion used in Grothendieck.hs and Analysis modules

import UnsafeCoerce

-- maps

type EndoMap a = FiniteMap a a

-- diagrams are just graphs

data Diagram object morphism = Graph object morphism

-- languages, define like "data CASL = CASL deriving Show" 

class Show lid => Language lid where
    language_name :: lid -> String
    language_name i = show i

-- (a bit unsafe) coercion using the language name
coerce :: (Language lid1, Language lid2) => lid1 -> lid2 -> a -> Maybe b
coerce i1 i2 a = if language_name i1 == language_name i2 then 
		 (Just $ unsafeCoerce a) else Nothing

rcoerce :: (Language lid1, Language lid2) => lid1 -> lid2 -> Pos-> a -> Result b
rcoerce i1 i2 pos a =
  maybeToResult pos 
                ("Logic "++ language_name i1 ++ " expected, but "
                            ++ language_name i2++" found")
                (coerce i1 i2 a)

-- Categories are given by a quotient,
-- i.e. we need equality
-- Should we allow arbitrary composition graphs and build paths?

class (Language lid, Eq sign, Show sign, Eq morphism) => 
      Category lid sign morphism | lid -> sign, lid -> morphism where
         ide :: lid -> sign -> morphism
         comp :: lid -> morphism -> morphism -> Maybe morphism
           -- diagrammatic order
         dom, cod :: lid -> morphism -> sign
         legal_obj :: lid -> sign -> Bool
         legal_mor :: lid -> morphism -> Bool

-- abstract syntax, parsing and printing

type ParseFun a = FilePath -> Int -> Int -> String -> (a,String,Int,Int)
                  -- args: filename, line, column, input text
                  -- result: value, remaining text, line, column 

class (Language lid, PrettyPrint basic_spec, Eq basic_spec,
       PrettyPrint symb_items, Eq symb_items,
       PrettyPrint symb_map_items, Eq symb_map_items) =>
      Syntax lid basic_spec symb_items symb_map_items
        | lid -> basic_spec, lid -> symb_items,
          lid -> symb_map_items
      where 
         -- parsing
         parse_basic_spec :: lid -> Maybe(ParseFun basic_spec)
         parse_symb_items :: lid -> Maybe(ParseFun symb_items)
         parse_symb_map_items :: lid -> Maybe(ParseFun symb_map_items)

-- sentences (plus prover stuff and "symbol" with "Ord" for efficient lookup)

class (Category lid sign morphism, Show sentence, 
       Ord symbol, Show symbol)
    => Sentences lid sentence sign morphism symbol
        | lid -> sentence, lid -> sign, lid -> morphism,
          lid -> symbol
      where
         -- sentence translation
      map_sen :: lid -> morphism -> sentence -> Result sentence
         -- parsing of sentences
      parse_sentence :: lid -> sign -> String -> Result sentence
           -- is a term parser needed as well?
      provers :: lid -> [Prover sentence symbol]
      cons_checkers :: lid -> [Cons_checker 
			      (TheoryMorphism sign sentence morphism)] 
-- static analysis

class ( Syntax lid basic_spec symb_items symb_map_items
      , Sentences lid sentence sign morphism symbol
      , Show raw_symbol, Eq raw_symbol)
    => StaticAnalysis lid 
        basic_spec sentence symb_items symb_map_items
        sign morphism symbol raw_symbol 
        | lid -> basic_spec, lid -> sentence, lid -> symb_items,
          lid -> symb_map_items, 
          lid -> sign, lid -> morphism, lid -> symbol, lid -> raw_symbol
      where
         -- static analysis of basic specifications and symbol maps
         basic_analysis :: lid -> 
                           Maybe((basic_spec,  -- abstract syntax tree
                            sign,   -- efficient table for env signature
                            GlobalAnnos) ->   -- global annotations
                           Result (sign,sign,[(String,sentence)]))
                           -- the first output sign is the accumulated sign
                           -- the second output sign united with the input sing
                           -- should yield the first output sign
         stat_symb_map_items :: 
	     lid -> [symb_map_items] -> Result (EndoMap raw_symbol)
         stat_symb_items :: lid -> [symb_items] -> Result [raw_symbol] 
         -- architectural sharing analysis for one morphism
         ensures_amalgamability :: lid ->
              (Diagram sign morphism, Node, sign, LEdge morphism, morphism) -> 
               Result (Diagram sign morphism)
         -- do we need it also for sinks consisting of two morphisms?

         -- symbols and symbol maps
         symbol_to_raw :: lid -> symbol -> raw_symbol
         id_to_raw :: lid -> Id -> raw_symbol 
         sym_of :: lid -> sign -> Set symbol
         symmap_of :: lid -> morphism -> EndoMap symbol
         matches :: lid -> symbol -> raw_symbol -> Bool
         sym_name :: lid -> symbol -> Id 
   
         -- operations on signatures and morphisms
         add_sign :: lid -> sign -> sign -> sign
         empty_signature :: lid -> sign
         signature_union :: lid -> sign -> sign -> Result sign
         final_union :: lid -> sign -> sign -> Result sign
         is_subsig :: lid -> sign -> sign -> Bool
         generated_sign, cogenerated_sign :: 
	     lid -> [symbol] -> sign -> Result morphism
         induced_from_morphism :: 
	     lid -> EndoMap raw_symbol -> sign -> Result morphism
         induced_from_to_morphism :: 
	     lid -> EndoMap raw_symbol -> sign -> sign -> Result morphism 
         extend_morphism :: 
	     lid -> sign -> morphism -> sign -> sign -> Result morphism

-- sublogics

class Ord l => LatticeWithTop l where
  meet, join :: l -> l -> l
  top :: l


-- logics

class (StaticAnalysis lid 
        basic_spec sentence symb_items symb_map_items
        sign morphism symbol raw_symbol,
       LatticeWithTop sublogics) =>
      Logic lid sublogics
        basic_spec sentence symb_items symb_map_items
        sign morphism symbol raw_symbol 
        | lid -> sublogics, lid -> basic_spec, lid -> sentence, lid -> symb_items,
          lid -> symb_map_items,
          lid -> sign, lid -> morphism, lid ->symbol, lid -> raw_symbol
	  where
         sublogic_names :: lid -> sublogics -> [String] 
             -- the first name is the principal name
         all_sublogics :: lid -> [sublogics]

         is_in_basic_spec :: lid -> sublogics -> basic_spec -> Bool
         is_in_sentence :: lid -> sublogics -> sentence -> Bool
         is_in_symb_items :: lid -> sublogics -> symb_items -> Bool
         is_in_symb_map_items :: lid -> sublogics -> symb_map_items -> Bool
         is_in_sign :: lid -> sublogics -> sign -> Bool
         is_in_morphism :: lid -> sublogics -> morphism -> Bool
         is_in_symbol :: lid -> sublogics -> symbol -> Bool

         min_sublogic_basic_spec :: lid -> basic_spec -> sublogics
         min_sublogic_sentence :: lid -> sentence -> sublogics
         min_sublogic_symb_items :: lid -> symb_items -> sublogics
         min_sublogic_symb_map_items :: lid -> symb_map_items -> sublogics
         min_sublogic_sign :: lid -> sign -> sublogics
         min_sublogic_morphism :: lid -> morphism -> sublogics
         min_sublogic_symbol :: lid -> symbol -> sublogics

         proj_sublogic_basic_spec :: lid -> sublogics -> basic_spec -> basic_spec
         proj_sublogic_symb_items :: lid -> sublogics -> symb_items -> Maybe symb_items
         proj_sublogic_symb_map_items :: lid -> sublogics -> symb_map_items -> Maybe symb_map_items
         proj_sublogic_sign :: lid -> sublogics -> sign -> sign 
         proj_sublogic_morphism :: lid -> sublogics -> morphism -> morphism
         proj_sublogic_epsilon :: lid -> sublogics -> sign -> morphism
         proj_sublogic_symbol :: lid -> sublogics -> symbol -> Maybe symbol


{- class hierarchy:
                            Language
               __________/     
   Category
      |                  /       
   Sentences      Syntax
      \            /
      StaticAnalysis (no sublogics)
            \                        
             \                             
            Logic

-}
