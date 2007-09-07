{- |
Module      :  $Header$
Description :  Pretty printing for SoftFOL problems in DFG.
Copyright   :  (c) Rene Wagner, C. Maeder, Uni Bremen 2005-2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  provisional
Portability :  portable

Pretty printing for SoftFOL signatures.
   Refer to <http://spass.mpi-sb.mpg.de/webspass/help/syntax/dfgsyntax.html>
   for the SPASS syntax documentation.
-}

module SoftFOL.Print (printFormula) where

import Data.Char (toLower)
import qualified Data.Map as Map
import Common.AS_Annotation
import Common.Doc
import Common.DocUtils

import SoftFOL.Sign

{- |
  Helper function.
-}
endOfListS :: Doc
endOfListS = text "end_of_list."

{- |
  Creates a Doc from a SPASS Problem.
-}
instance Pretty SPProblem where
  pretty p = text "begin_problem" <> parens (text (identifier p)) <> dot
    $++$ pretty (description p)
    $++$ pretty (logicalPart p)
    $++$ printSettings (settings p)
    $++$ text "end_problem."

{- |
  Creates a Doc from a SPASS Logical Part.
-}
instance Pretty SPLogicalPart where
  pretty lp = pretty (symbolList lp)
       $++$ (case declarationList lp of
         Nothing -> empty
         Just l -> text "list_of_declarations."
           $+$ vcat (map pretty l)
           $+$ endOfListS)
       $++$ vcat (map pretty $ formulaLists lp)
       $++$ vcat (map pretty $ clauseLists lp)
       $++$ vcat (map pretty $ proofLists lp)

{- |
  Creates a Doc from a SPASS Symbol List.
-}
instance Pretty SPSymbolList where
  pretty sl = text "list_of_symbols."
    $+$ printSignSymList "functions"   (functions sl)
    $+$ printSignSymList "predicates"  (predicates sl)
    $+$ (if null $ sorts sl then empty else
         text "sorts" <> brackets (ppWithCommas $ sorts sl) <> dot)
    $+$ endOfListS
    where
      printSignSymList lname list = if null list then empty else
        cat [ text lname
            , brackets (fsep $ punctuate comma $ map pretty list) <> dot]

{-|
  Helper function. Creates a Doc from a Signature Symbol.
-}
instance Pretty SPSignSym where
  pretty ssym = case ssym of
      SPSimpleSignSym s -> text s
      _ -> parens (text (sym ssym) <> comma <+> pretty (arity ssym))

{- |
  Creates a Doc from a SPASS Declaration
-}
instance Pretty SPDeclaration where
  pretty d = case d of
    SPSubsortDecl {sortSymA= a, sortSymB= b} ->
      text "subsort" <> parens (text a <> comma <+> text b) <> dot
    SPTermDecl {termDeclTermList= l, termDeclTerm= t} ->
      pretty (SPQuantTerm {quantSym= SPForall, variableList= l, qFormula= t})
        <> dot
    SPSimpleTermDecl t -> pretty t <> dot
    SPPredDecl {predSym= p, sortSyms= slist} ->
      pretty (SPComplexTerm {symbol= (SPCustomSymbol "predicate"), arguments=
          (map (\ x -> SPSimpleTerm (SPCustomSymbol x)) (p : slist))}) <> dot
    SPGenDecl {sortSym= s, freelyGenerated= freelygen, funcList= l} ->
      text "sort" <+> text s <+> (if freelygen then text "freely" else empty)
        <+> text "generated by"
        <+> brackets (fsep $ punctuate comma $ map text l) <> dot

{- |
  Creates a Doc from a SPASS Formula List
-}
instance Pretty SPFormulaList where
  pretty l = text "list_of_formulae" <> parens (pretty (originType l)) <> dot
    $+$ vcat (map (\ x -> printFormula x <> dot) $ formulae l)
    $+$ endOfListS

instance Pretty SPClauseList where
  pretty l = text "list_of_clauses" <> parens (pretty (coriginType l)
           <> comma <+> pretty (clauseType l)) <> dot
    $+$ vcat (map (\ x -> printClause x <> dot) $ clauses l)
    $+$ endOfListS

instance Pretty SPProofList where
  pretty l = text "list_of_proof" <> maybe empty
    (parens . (<> printAssocList (plAssocList l)) . pretty) (proofType l)
      <> dot
    $+$ vcat (map (\ x -> printStep x <> dot) $ step l)
    $+$ endOfListS

printAssocList :: SPAssocList -> Doc
printAssocList m = if Map.null m then empty else comma <+>
    brackets (fsep $ punctuate comma $ map
      ( \ (k, v) -> pretty k <> text ":" <> pretty v) $ Map.toList m)

instance Pretty SPKey where
    pretty (PKeyTerm t) = pretty t

instance Pretty SPValue where
    pretty (PValTerm t) = pretty t

{- |
  Creates a Doc from a SPASS Origin Type
-}
instance Pretty SPOriginType where
  pretty t = text $ case t of
    SPOriginAxioms -> "axioms"
    SPOriginConjectures -> "conjectures"

instance Pretty SPClauseType where
  pretty t = text $ case t of
    SPCNF -> "cnf"
    SPDNF -> "dnf"

{- |
  Creates a Doc from a SPASS Formula. Needed since SPFormula is just a
  'type SPFormula = Named SPTerm' and thus instanciating Pretty is not
  possible.
-}
printFormula :: SPFormula -> Doc
printFormula f = text "formula" <> parens (pretty (sentence f) <>
    case senAttr f of
      "" -> empty
      s -> comma <+> text s)

printClause :: SPClause -> Doc
printClause c = text "clause" <> parens (pretty (sentence c) <>
    case senAttr c of
      "" -> empty
      s -> comma <+> text s)

instance Pretty NSPClause where
    pretty t = case t of
        QuanClause vs b -> text (case b of
              NSPCNF _ -> "forall"
              NSPDNF _ -> "exists") <>
            parens (brackets (ppWithCommas vs) <> comma <+> pretty b)
        SimpleClause b -> pretty b
        BriefClause l1 l2 l3 -> pretty l1 <+> text "||"
                <+> pretty l2 <+> text "->" <+> pretty l3

instance Pretty NSPClauseBody where
    pretty t = case t of
        NSPCNF l -> text "or" <> parens (ppWithCommas l)
        NSPDNF l -> text "and" <> parens (ppWithCommas l)

instance Pretty SPLiteral where
    pretty l = case l of
        NSPFalse -> text "false"
        NSPTrue -> text "true"
        NSPPLit t -> pretty t
        NSPNotPLit t -> text "not" <> parens (pretty t)

instance Pretty TermWsList where
    pretty (TWL l b) = fsep (map pretty l) <> if b then text "+" else empty

printStep :: SPProofStep -> Doc
printStep (SPProofStep ref res rul parl asl) = text "step" <> parens
      (pretty ref <> comma <+> pretty res <> comma <+> pretty rul <> comma
       <+> brackets (ppWithCommas parl) <> printAssocList asl) <> dot

instance Pretty SPReference where
    pretty (PRefTerm t) = pretty t

instance Pretty SPResult where
    pretty (PResTerm t) = pretty t

instance Pretty SPRuleAppl where
    pretty r = case r of
        PRuleTerm t -> pretty t
        PRuleUser t -> pretty t

instance Pretty SPUserRuleAppl where
    pretty r = text $ show r

instance Pretty SPParent where
    pretty (PParTerm t) = pretty t

{- |
  Creates a Doc from a SPASS Term.
-}
instance Pretty SPTerm where
  pretty t = case t of
    SPQuantTerm{quantSym= qsym, variableList= tlist, qFormula= tt} ->
        pretty qsym <>
        parens (brackets (ppWithCommas tlist) <> comma <+> pretty tt)
    SPSimpleTerm stsym -> pretty stsym
    SPComplexTerm{symbol= ctsym, arguments= args} ->
        pretty ctsym <> if null args then empty else parens (ppWithCommas args)

{- |
  Creates a Doc from a SPASS Quantifier Symbol.
-}
instance Pretty SPQuantSym where
  pretty qs = text $ case qs of
    SPForall -> "forall"
    SPExists -> "exists"
    SPCustomQuantSym cst -> cst

{- |
  Creates a Doc from a SPASS Symbol.
-}
-- printSymbol :: SPSymbol-> Doc
instance Pretty SPSymbol where
    pretty s = text $ case s of
     SPCustomSymbol cst -> cst
     _ -> map toLower $ drop 2 $ show s

{- |
  Creates a Doc from a SPASS description.
-}
instance Pretty SPDescription where
  pretty d =
    let sptext str v = text str <> parens (textBraces $ text v) <> dot
        mtext str = maybe empty $ sptext str
    in text "list_of_descriptions."
    $+$ sptext "name" (name d)
    $+$ sptext "author" (author d)
    $+$ mtext "version" (version d)
    $+$ mtext "logic" (logic d)
    $+$ text "status" <> parens (pretty $ status d) <> dot
    $+$ sptext "description" (desc d)
    $+$ mtext "date" (date d)
    $+$ endOfListS

{- |
  surrounds  a doc with "{*  *}" as required for some of the
  description fields and the settings.
-}
textBraces :: Doc -> Doc
textBraces d = text "{* " <> d <> text " *}"

{- |
  Creates a Doc from an 'SPLogState'.
-}
instance Pretty SPLogState where
  pretty s = text $ case s of
    SPStateSatisfiable -> "satisfiable"
    SPStateUnsatisfiable -> "unsatisfiable"
    SPStateUnknown -> "unknown"

printSettings :: [SPSetting] -> Doc
printSettings = vcat . map pretty

instance Pretty SPSetting where
    pretty (SPGeneralSettings es) =
        text "list_of_general_settings."
        $+$ vcat (map pretty es)
        $+$ endOfListS
    pretty (SPSettings label body) =
        text "list_of_settings" <> parens (pretty label) <> dot
        $+$ textBraces (hcat $ map pretty body)
        $+$ endOfListS

instance Pretty SPSettingLabel where
    pretty l = text $ case l of
        ThreeTAP -> "3TAP"
        _ -> show l

instance Pretty SPHypothesis where
    pretty (SPHypothesis ls) =
        text "hypothesis" <> brackets (ppWithCommas ls) <> dot

instance Pretty SPSettingBody where
    pretty (SPFlag sw v) =
        text sw <> parens (ppWithCommas v) <> dot
    pretty (SPClauseRelation cfrList) = text "set_ClauseFormulaRelation"
       <> parens (ppWithCommas cfrList) <> dot

instance Pretty SPCRBIND where
    pretty (SPCRBIND cSPR fSPR) = parens $ text cSPR <> comma <+> text fSPR
