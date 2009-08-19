{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances #-}
{- |
Module      :  $Header$
Description :  extracted annotated items as strings from BASIC_SPEC
Copyright   :  (c) Christian Maeder and Ewaryst Schulz  and DFKI GmbH 2009
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Ewaryst.Schulz@dfki.de
Stability   :  experimental
Portability :  non-portable

get item representation of 'BASIC_SPEC'
-}

module CASL.ToItem (bsToItem) where

import Control.Monad.Reader

import Common.AS_Annotation
import Common.Doc
import Common.DocUtils
import Common.Id
import Common.Item

import CASL.AS_Basic_CASL
import CASL.ToDoc
import CASL.Fold

--------------------- utils

toString :: Pretty a => a -> String
toString = show . pretty

--------------------- TS = TransState
data TS b s f = TS { fB :: (b -> Doc)
                   , fS :: (s -> Doc)
                   , fF :: (f -> Doc) }

-- LITC = LocalITContext
-- This datastructure is used to pass an additional ItemType argument to
-- the toitem method when one needs an instance for which this method
-- should behave differently in different contexts depending on this argument.
-- Typically the ItemType is used as ItemType of the Item to be created.

data LITC a = LITC ItemType a

--------------------- lifting to Local Contexts
withLIT :: ItemTypeable a => a -> b -> LITC b
withLIT it = LITC $ toIT it

listWithLIT :: ItemTypeable a => a -> [b] -> [LITC b]
listWithLIT it = map (withLIT it)

-- analogous for annotated objects, don't needed yet
--annWithLIT :: ItemTypeable a => a -> Annoted b -> Annoted (LITC b)
--annWithLIT it = fmap (withLIT it)

--annlistWithLIT :: ItemTypeable a => a -> [Annoted b] -> [Annoted (LITC b)]
--annlistWithLIT it = map (annWithLIT it)


-- this function is only to unify the types of the state and the basic spec
-- in the call of toitem and runState in bsToItem
getTransState :: (Pretty b, Pretty s, Pretty f) => BASIC_SPEC b s f ->
                 TS b s f
getTransState _ = TS pretty pretty pretty

--------------------- The Main function of this module
bsToItem :: (Pretty b, Pretty s, Pretty f) => (BASIC_SPEC b s f) -> Item
bsToItem bs = runReader (toitem bs) $ getTransState bs





instance ItemConvertible (BASIC_SPEC b s f) (Reader (TS b s f)) where
    toitem (Basic_spec l) =
        do{ l' <-  listFromAL l
          ; return rootItem{ items = l' } }

instance ItemConvertible (BASIC_ITEMS b s f) (Reader (TS b s f)) where
    toitem bi =
        case bi of
          Sig_items s -> toitem s
          Var_items l (Range qs) -> mkItemM "Var_items"
             (Range . joinRanges $ qs : map varDeclRange l) $ listFromL l
          Axiom_items al (Range qs) -> mkItemM "Axiom_items"
             (Range . joinRanges $ qs : map (annoRange formulaRange) al)
             $ listFromAL al
          Local_var_axioms vl fl (Range qs) ->
              mkItemMM "Local_var_axioms"
                 (Range . joinRanges $ qs : map varDeclRange vl ++
                       map (annoRange formulaRange) fl)
                           [fromL "VAR_DECLS" vl, fromAL "FORMULAS" fl]
          Sort_gen asis rg -> mkItemM "Sort_gen" rg $ listFromAL asis
          Free_datatype sk adtds rg ->
              mkItemM ("Free_datatype", "SortsKind", show sk) rg
                          $ listFromAL adtds
          Ext_BASIC_ITEMS b ->
              do{ st <- ask
                ; fromPrinter (show . (fB st)) "Ext_BASIC_ITEMS" b }

instance ItemConvertible (SIG_ITEMS s f) (Reader (TS b s f)) where
    toitem si =
        case si of
          Sort_items sk sis rg ->
              mkItemM ("Sort_items", "SortsKind", show sk) rg
                $ listFromAL sis
          Op_items aois rg -> mkItemM "Op_items" rg $ listFromAL aois
          Pred_items apis rg -> mkItemM "Pred_items" rg $ listFromAL apis
          Datatype_items sk adds rg ->
              mkItemM ("Datatype_items", "SortsKind", show sk) rg
                $ listFromAL adds
          Ext_SIG_ITEMS s ->
              do{ st <- ask
                ; fromPrinter (show . (fS st)) "Ext_SIG_ITEMS" s }


instance ItemConvertible (SORT_ITEM f) (Reader (TS b s f)) where
    toitem si =
        case si of
          Sort_decl l rg -> mkItemM "Sort_decl" rg $ listFromL
                            $ listWithLIT "SORT" l
          Subsort_decl sl s rg -> mkItemMM "Subsort_decl" rg
                                  [ fromL "SORTS" $ listWithLIT "SORT" sl
                                  , fromC $ withLIT "SORT" s]
          Subsort_defn s v s' f rg ->
              mkItemMM "Subsort_defn" rg
                [ fromC $ withLIT "SORT" s, fromC $ withLIT "VAR" v
                , fromC $ withLIT "SORT" s', fromAC f]
          Iso_decl l rg -> mkItemM "Iso_decl" rg $ listFromL
                           $ listWithLIT "SORT" l


instance ItemConvertible (OP_ITEM f) (Reader (TS b s f)) where
    toitem oi =
        case oi of
          Op_decl onl ot oal rg ->
              mkItemMM "Op_decl" rg
                [ fromL "OP_NAMES" $ listWithLIT "OP_NAME" onl, fromC ot
                , fromL "OP_ATTRIBS" oal]
          Op_defn on oh at rg ->
              mkItemMM "Op_defn" rg [ fromC $ withLIT "OP_NAME" on, fromC oh
                                    , fromAC at]


instance ItemConvertible (PRED_ITEM f) (Reader (TS b s f)) where
    toitem p =
        case p of
          Pred_decl pnl pt rg ->
              mkItemMM "Pred_decl" rg
                [fromL "PRED_NAMES" $ listWithLIT "PRED_NAME" pnl, fromC pt]
          Pred_defn pn ph af rg ->
              mkItemMM "Pred_defn" rg [ fromC $ withLIT "PRED_NAME" pn, fromC ph
                                      , fromAC af]


-------------------- not further expanded --------------------

fromPrinterWithRg :: (Monad m, GetRange a) =>
                     (a -> String) -> String -> a -> m Item
fromPrinterWithRg = fromPrinterWithRange getRange

fromPrinterWithRange
    :: Monad m => (a -> Range) -> (a -> String) -> String -> a -> m Item
fromPrinterWithRange r p n o = mkItemMM (n, p o) (r o) []

fromPrinter :: Monad m => (a -> String) -> String -> a -> m Item
fromPrinter p n o = mkItemMM (n, p o) nullRange []

litFromPrinterWithRg :: (Monad m, GetRange a) =>
                        (a -> String) -> LITC a -> m Item
litFromPrinterWithRg p (LITC (IT l) o) =
    mkItemMM (IT $ l ++ [p o]) (getRange o) []


instance ItemConvertible OP_TYPE (Reader (TS b s f)) where
    toitem = fromPrinterWithRg toString "OP_TYPE"

instance ItemConvertible OP_HEAD (Reader (TS b s f)) where
    toitem = fromPrinterWithRg toString "OP_HEAD"

instance ItemConvertible (OP_ATTR f) (Reader (TS b s f)) where
    toitem a =
        do{ st <- ask
          ; fromPrinter (show . printAttr (fF st)) "OP_ATTR" a }

instance ItemConvertible PRED_TYPE (Reader (TS b s f)) where
    toitem = fromPrinterWithRg toString "PRED_TYPE"

instance ItemConvertible PRED_HEAD (Reader (TS b s f)) where
    toitem = fromPrinterWithRg (show . printPredHead) "PRED_HEAD"

instance ItemConvertible DATATYPE_DECL (Reader (TS b s f)) where
    toitem = fromPrinterWithRg toString "DATATYPE_DECL"

instance ItemConvertible VAR_DECL (Reader (TS b s f)) where
    toitem = fromPrinterWithRg toString "VAR_DECL"

instance ItemConvertible (FORMULA f) (Reader (TS b s f)) where
    toitem f = do
      st <- ask
      fromPrinterWithRange (Range . formulaRange)
               (show . printFormula (fF st)) "FORMULA" f

instance ItemConvertible (TERM f) (Reader (TS b s f)) where
    toitem f = do
      st <- ask
      fromPrinterWithRange (Range . termRange)
               (show . printTerm (fF st)) "TERM" f

instance ItemConvertible (LITC Id) (Reader (TS b s f)) where
    toitem = litFromPrinterWithRg toString

instance ItemConvertible (LITC Token) (Reader (TS b s f)) where
    toitem = litFromPrinterWithRg toString


