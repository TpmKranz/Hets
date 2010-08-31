{- |
Module      :  $Header$
Description :  table for statistical reports
Copyright   :  (c) Immanuel Normann, Uni Bremen 2007
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  inormann@jacobs-university.de
Stability   :  provisional
Portability :  non-portable
-}
---------------------------------------------------------------------------
-- Generated by DB/Direct
---------------------------------------------------------------------------
module Search.DB.MPTP.Statistics where

import Database.HaskellDB.DBLayout

---------------------------------------------------------------------------
-- Table
---------------------------------------------------------------------------
statistics :: Table
    ((RecCons Library (Expr String)
      (RecCons File (Expr String)
       (RecCons Tautologies (Expr Int)
        (RecCons Duplicates (Expr Int)
         (RecCons Formulae (Expr Int) RecNil))))))

statistics = baseTable "statistics" $
             hdbMakeEntry Library #
             hdbMakeEntry File #
             hdbMakeEntry Tautologies #
             hdbMakeEntry Duplicates #
             hdbMakeEntry Formulae

---------------------------------------------------------------------------
-- Fields
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Library Field
---------------------------------------------------------------------------

data Library = Library

instance FieldTag Library where fieldName _ = "library"

library :: Attr Library String
library = mkAttr Library

---------------------------------------------------------------------------
-- File Field
---------------------------------------------------------------------------

data File = File

instance FieldTag File where fieldName _ = "file"

file :: Attr File String
file = mkAttr File

---------------------------------------------------------------------------
-- Tautologies Field
---------------------------------------------------------------------------

data Tautologies = Tautologies

instance FieldTag Tautologies where fieldName _ = "tautologies"

tautologies :: Attr Tautologies Int
tautologies = mkAttr Tautologies

---------------------------------------------------------------------------
-- Duplicates Field
---------------------------------------------------------------------------

data Duplicates = Duplicates

instance FieldTag Duplicates where fieldName _ = "duplicates"

duplicates :: Attr Duplicates Int
duplicates = mkAttr Duplicates

---------------------------------------------------------------------------
-- Formulae Field
---------------------------------------------------------------------------

data Formulae = Formulae

instance FieldTag Formulae where fieldName _ = "formulae"

formulae :: Attr Formulae Int
formulae = mkAttr Formulae
