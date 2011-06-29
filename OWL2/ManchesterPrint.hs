{- |
Module      :  $Header$
Copyright   :  (c) Felix Gabriel Mance
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  f.mance@jacobs-university.de
Stability   :  provisional
Portability :  portable

Contains    :  Pretty printing for the Manchester Syntax of OWL 2
-}

module OWL2.ManchesterPrint where

import Common.Doc
import Common.DocUtils
import Common.Keywords

import OWL2.AS
import OWL2.MS
import OWL2.Print
import OWL2.Keywords
import OWL2.ColonKeywords
import qualified Data.Map as Map

printCharact :: String -> Doc
printCharact = text

instance Pretty Character where
  pretty = printCharact . show

instance Pretty a => Pretty (AnnotatedList a) where
    pretty = printAnnotatedList

printAnnotatedList :: Pretty a => AnnotatedList a -> Doc
printAnnotatedList (AnnotatedList l) =
  vcat $ punctuate comma $ map
    ( \ (ans, a) -> printAnnotations ans $+$ pretty a) l

instance Pretty FrameBit where
    pretty = printFrameBit

printFrameBit :: FrameBit -> Doc
printFrameBit fb = case fb of
    AnnotationFrameBit x -> printAnnotations x
    AnnotationBit ed l -> printRelation ed <+> pretty l
    DatatypeBit ans a -> printAnnotations ans
          $+$ keyword equivalentToC <+> pretty a
    ExpressionBit x y -> printRelation x <+> pretty y
    ClassDisjointUnion a x -> keyword disjointUnionOfC
      <+> (printAnnotations a
          $+$ vcat (punctuate comma ( map pretty x )))
    ClassHasKey a op dp -> keyword hasKeyC <+> (printAnnotations a
      $+$ vcat (punctuate comma $ map pretty op ++ map pretty dp))
    ObjectBit dr x -> printRelation dr <+> pretty x
    ObjectCharacteristics x -> keyword characteristicsC <+> pretty x
    ObjectSubPropertyChain a opl -> keyword subPropertyChainC
      <+> (printAnnotations a $+$ fsep (prepPunctuate (keyword oS <> space)
          $ map pretty opl))
    DataBit dr x -> printRelation dr <+> pretty x
    DataPropRange x -> keyword rangeC <+> pretty x
    DataFunctional x -> keyword characteristicsC <+>
          (printAnnotations x $+$ printCharact functionalS)
    IndividualFacts x -> keyword factsC <+> pretty x
    IndividualSameOrDifferent s x -> printSameOrDifferent s <+> pretty x

instance Pretty Fact where
    pretty = printFact

printFact :: Fact -> Doc
printFact pf = case pf of
    ObjectPropertyFact pn op i -> printPositiveOrNegative pn
           <+> pretty op <+> pretty i
    DataPropertyFact pn dp l -> printPositiveOrNegative pn
           <+> pretty dp <+> pretty l

printPositiveOrNegative :: PositiveOrNegative -> Doc
printPositiveOrNegative x = case x of
    Positive -> empty
    Negative -> keyword notS

instance Pretty Frame where
    pretty = printFrame

printFrame :: Frame -> Doc
printFrame f = case f of
    Frame (Entity e uri) bl -> pretty (showEntityType e) <+>
            fsep [pretty uri, vcat (map pretty bl)]
    MiscFrame e a misc -> case misc of
        MiscEquivOrDisjointClasses c -> printEquivOrDisjointClasses e <+>
            (printAnnotations a $+$ vcat (punctuate comma (map pretty c) ))
        MiscEquivOrDisjointObjProp c -> printEquivOrDisjointProp e <+>
            (printAnnotations a $+$ vcat (punctuate comma (map pretty c) ))
        MiscEquivOrDisjointDataProp c -> printEquivOrDisjointProp e <+>
            (printAnnotations a $+$ vcat (punctuate comma (map pretty c) ))
    MiscSameOrDifferent s a c -> printSameOrDifferentInd s <+>
            (printAnnotations a $+$ vcat (punctuate comma (map pretty c) ))

instance Pretty MOntology where
    pretty = printOntology

printImport :: ImportIRI -> Doc
printImport x = keyword importC <+> pretty x

printPrefixes :: PrefixMap -> Doc
printPrefixes x = vcat (map (\ (a, b) ->
       (text "Prefix:" <+> text a <> colon <+> text ('<' : b ++ ">")))
          (Map.toList x))

printOntology :: MOntology -> Doc
printOntology MOntology {muri = a, imports = b, ann = c, ontologyFrame = d} =
        keyword ontologyC <+> pretty a $++$ vcat (map printImport b)
        $++$ vcat (map printAnnotations c) $+$ vcat (map pretty d)

printOntologyDocument :: OntologyDocument -> Doc
printOntologyDocument OntologyDocument {prefixDeclaration = a, mOntology = b} =
        printPrefixes a $++$ pretty b

instance Pretty OntologyDocument where
    pretty = printOntologyDocument
