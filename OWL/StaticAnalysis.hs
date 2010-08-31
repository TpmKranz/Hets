{- |
Module      :  $Header$
Copyright   :  Heng Jiang, Uni Bremen 2004-2007
License     :  GPLv2 or higher, see LICENSE.txt

Maintainer  :  luecke@informatik.uni-bremen.de
Stability   :  provisional
Portability :  portable

static analysis of basic specifications for OWL 1.1.
-}

module OWL.StaticAnalysis (basicOWLAnalysis, modEntity) where

import OWL.Namespace
import OWL.Sign
import OWL.AS

import qualified Data.Set as Set
import qualified Data.Map as Map

import Common.AS_Annotation
import Common.Result
import Common.GlobalAnnotations
import Common.ExtSign
import Common.Lib.State

modEntity :: (URI -> Set.Set URI -> Set.Set URI) -> Entity -> State Sign ()
modEntity f (Entity ty u) = do
  s <- get
  let chg = f u
  put $ case ty of
    Datatype -> s { datatypes = chg $ datatypes s }
    Class -> s { concepts = chg $ concepts s }
    ObjectProperty -> s { indValuedRoles = chg $ indValuedRoles s }
    DataProperty -> s { dataValuedRoles = chg $ dataValuedRoles s }
    NamedIndividual -> s { individuals = chg $ individuals s }
    AnnotationProperty -> s -- ignore

addEntity :: Entity -> State Sign ()
addEntity = modEntity Set.insert

anaAxiom :: Axiom -> State Sign [Named Axiom]
anaAxiom an = case an of
  EntityAnno (EntityAnnotation _ e _) -> do
    addEntity e
    return []
  PlainAxiom as p -> do
    anaPlainAxiom p
    return [findImplied as $ makeNamed "" an]

anaObjPropExpr :: ObjectPropertyExpression -> State Sign ()
anaObjPropExpr = addEntity . Entity ObjectProperty . getObjRoleFromExpression

anaDataPropExpr :: DataPropertyExpression -> State Sign ()
anaDataPropExpr = addEntity . Entity DataProperty

anaIndividual :: IndividualURI -> State Sign ()
anaIndividual = addEntity . Entity NamedIndividual

anaConstant :: Constant -> State Sign ()
anaConstant (Constant _ ty) = case ty of
  Typed u -> addEntity $ Entity Datatype u
  _ -> return ()

anaDataRange :: DataRange -> State Sign ()
anaDataRange dr = case dr of
  DRDatatype u -> addEntity $ Entity Datatype u
  DataComplementOf r -> anaDataRange r
  DataOneOf cs -> mapM_ anaConstant cs
  DatatypeRestriction r fcs -> do
    anaDataRange r
    mapM_ (anaConstant . snd) fcs

anaDescription :: Description -> State Sign ()
anaDescription desc = case desc of
  OWLClassDescription u ->
      case u of
        QN _ "Thing" _ _ -> addEntity $ Entity Class $
                          QN "owl" "Thing" False ""
        QN _ "Nothing" _ _ -> addEntity $ Entity Class $
                          QN "owl" "Nothing" False ""
        v -> addEntity $ Entity Class v
  ObjectJunction _ ds -> mapM_ anaDescription ds
  ObjectComplementOf d -> anaDescription d
  ObjectOneOf is -> mapM_ anaIndividual is
  ObjectValuesFrom _ opExpr d -> do
    anaObjPropExpr opExpr
    anaDescription d
  ObjectExistsSelf opExpr -> anaObjPropExpr opExpr
  ObjectHasValue opExpr i -> do
    anaObjPropExpr opExpr
    anaIndividual i
  ObjectCardinality (Cardinality _ _ opExpr md) -> do
    anaObjPropExpr opExpr
    maybe (return ()) anaDescription md
  DataValuesFrom _ dExp ds r -> do
    anaDataPropExpr dExp
    mapM_ anaDataPropExpr ds
    anaDataRange r
  DataHasValue dExp c -> do
    anaDataPropExpr dExp
    anaConstant c
  DataCardinality (Cardinality _ _ dExp mr) -> do
    anaDataPropExpr dExp
    maybe (return ()) anaDataRange mr

anaPlainAxiom :: PlainAxiom -> State Sign ()
anaPlainAxiom pa = case pa of
  SubClassOf s1 s2 -> do
    anaDescription s1
    anaDescription s2
  EquivOrDisjointClasses _ ds ->
    mapM_ anaDescription ds
  DisjointUnion u ds -> do
    addEntity $ Entity Class u
    mapM_ anaDescription ds
  SubObjectPropertyOf sop op -> do
    mapM_ (addEntity . Entity ObjectProperty)
      $ getObjRoleFromSubExpression sop
    anaObjPropExpr op
  EquivOrDisjointObjectProperties _ os ->
    mapM_ anaObjPropExpr os
  ObjectPropertyDomainOrRange _ op d -> do
    anaObjPropExpr op
    anaDescription d
  InverseObjectProperties o1 o2 -> do
    anaObjPropExpr o1
    anaObjPropExpr o2
  ObjectPropertyCharacter _ op -> anaObjPropExpr op
  SubDataPropertyOf d1 d2 -> do
    anaDataPropExpr d1
    anaDataPropExpr d2
  EquivOrDisjointDataProperties _ ds ->
    mapM_ anaDataPropExpr ds
  DataPropertyDomainOrRange ddr dp -> do
    case ddr of
      DataDomain d -> anaDescription d
      DataRange r -> anaDataRange r
    anaDataPropExpr dp
  FunctionalDataProperty dp -> anaDataPropExpr dp
  SameOrDifferentIndividual _ is ->
    mapM_ anaIndividual is
  ClassAssertion i d -> do
    anaIndividual i
    anaDescription d
  ObjectPropertyAssertion (Assertion op _ s t) -> do
    anaObjPropExpr op
    anaIndividual s
    anaIndividual t
  DataPropertyAssertion (Assertion dp _ s c) -> do
    anaDataPropExpr dp
    anaIndividual s
    anaConstant c
  Declaration e -> addEntity e

-- | static analysis of ontology with incoming sign.
basicOWLAnalysis ::
    (OntologyFile, Sign, GlobalAnnos) ->
        Result (OntologyFile, ExtSign Sign Entity, [Named Axiom])
basicOWLAnalysis (ofile, inSign, _) =
    let ns = namespaces ofile
        diags1 = foldl (++) [] (map isNamespaceInImport
                         (Map.elems (removeDefault ns)))
        (integNamespace, transMap) =
            integrateNamespaces (namespaceMap inSign) ns
        ofile' = renameNamespace transMap ofile
        syms = Set.difference (symOf accSign) $ symOf inSign
        (sens, accSign) = runState
          (mapM anaAxiom $ axiomsList $ ontology ofile')
          inSign {namespaceMap = integNamespace
                 , ontologyID = uri $ ontology ofile'
                 }
    in Result diags1
           $ Just (ofile', ExtSign accSign syms, concat sens)
    where
        oName = uri $ ontology ofile

        isNamespaceInImport :: String -> [Diagnosis]
        isNamespaceInImport iuri =
          if null iuri then []
            else
             let uri' = take (length iuri - 1) iuri
             in if elem uri' importList
                  then []
                  else
                    [mkDiag
                        Warning
                        ("\"" ++ uri' ++ "\"" ++
                                  " is not imported in ontology: " ++
                                  show (localPart oName))
                        ()]
        importList = localPart oName
          : map localPart (importsList $ ontology ofile)

        removeDefault :: Namespace -> Namespace
        removeDefault ns =
            foldr Map.delete ns
            ["owl11", "owl", "xsd", "rdf", "rdfs", "xml", "owl2xml"]

getObjRoleFromExpression :: ObjectPropertyExpression -> IndividualRoleURI
getObjRoleFromExpression opExp =
    case opExp of
       OpURI u -> u
       InverseOp objProp -> getObjRoleFromExpression objProp

getObjRoleFromSubExpression :: SubObjectPropertyExpression
                            -> [IndividualRoleURI]
getObjRoleFromSubExpression sopExp =
    case sopExp of
      OPExpression opExp -> [getObjRoleFromExpression opExp]
      SubObjectPropertyChain expList ->
          map getObjRoleFromExpression expList

findImplied :: [OWL.AS.Annotation] -> Named Axiom -> Named Axiom
findImplied anno sent =
  if isToProve anno then sent
         { isAxiom = False
         , isDef = False
         , wasTheorem = False }
  else sent { isAxiom = True }

isToProve :: [OWL.AS.Annotation] -> Bool
isToProve [] = False
isToProve (anno : r) =
    case anno of
      ExplicitAnnotation auri (Constant value (Typed _)) ->
          if localPart auri == "Implied" then value == "true"
            else isToProve r
      _ -> isToProve r
