{- |
Module      :  $Header$
Copyright   :  (c) Till Mossakowski, and Uni Bremen 2002-2004
Licence     :  similar to LGPL, see HetCATS/LICENCE.txt or LIZENZ.txt

Maintainer  :  till@tzi.de
Stability   :  provisional
Portability :  non-portable (overlapping instances, dynamics, existentials)

   
   The Grothendieck logic is defined to be the
   heterogeneous logic over the logic graph.
   This will be the logic over which the data 
   structures and algorithms for specification in-the-large
   are built.

   References:

   R. Diaconescu:
   Grothendieck institutions
   J. applied categorical structures 10, 2002, p. 383-402.

   T. Mossakowski: 
   Heterogeneous development graphs and heterogeneous borrowing
   Fossacs 2002, LNCS 2303, p. 326-341

   T. Mossakowski: Foundations of heterogeneous specification
   Submitted

   T. Mossakowski:
   Relating CASL with Other Specification Languages:
        the Institution Level
   Theoretical Computer Science 286, 2002, p. 367-475

   Todo:

-}

module Logic.Grothendieck where

import Logic.Logic
import Logic.Prover
import Logic.Comorphism
import Common.PrettyPrint
import Common.Lib.Pretty
import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import Common.Result
import Common.Id
import Common.AS_Annotation
import Common.ListUtils
import Data.Dynamic
import qualified Data.List as List
import Data.Maybe
import Control.Monad

import Common.Lib.Parsec.Pos -- for testing purposes

------------------------------------------------------------------
--"Grothendieck" versions of the various parts of type class Logic
------------------------------------------------------------------

-- | Grothendieck basic specifications
data G_basic_spec = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
  G_basic_spec lid basic_spec 

instance Show G_basic_spec where
    show (G_basic_spec _ s) = show s

instance PrettyPrint G_basic_spec where
    printText0 ga (G_basic_spec _ s) = printText0 ga s

-- | Grothendieck sentences
data G_sentence = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
  G_sentence lid sentence 

instance Show G_sentence where
    show (G_sentence _ s) = show s

-- | Grothendieck sentence lists
data G_l_sentence_list = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree  =>
  G_l_sentence_list lid [Named sentence] 

instance Show G_l_sentence_list where
    show (G_l_sentence_list _ s) = show s

instance Eq G_l_sentence_list where
    (G_l_sentence_list i1 nl1) == (G_l_sentence_list i2 nl2) =
      coerce i1 i2 nl1 == Just nl2

eq_G_l_sentence_set :: G_l_sentence_list -> G_l_sentence_list -> Bool
eq_G_l_sentence_set (G_l_sentence_list i1 nl1) (G_l_sentence_list i2 nl2) =
     case coerce i1 i2 nl1 of
       Just nl1' -> Set.fromList nl1' == Set.fromList nl2
       Nothing -> False

-- | Grothendieck signatures
data G_sign = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
  G_sign lid sign 

tyconG_sign :: TyCon
tyconG_sign = mkTyCon "Logic.Grothendieck.G_sign"
instance Typeable G_sign where
  typeOf _ = mkTyConApp tyconG_sign []

instance Eq G_sign where
  (G_sign i1 sigma1) == (G_sign i2 sigma2) =
     coerce i1 i2 sigma1 == Just sigma2

-- | prefer a faster subsignature test if possible
is_subgsign :: G_sign -> G_sign -> Bool
is_subgsign (G_sign i1 sigma1) (G_sign i2 sigma2) = 
    maybe False (is_subsig i1 sigma1) $ coerce i2 i1 sigma2 

instance Show G_sign where
    show (G_sign _ s) = show s

instance PrettyPrint G_sign where
    printText0 ga (G_sign _ s) = printText0 ga s

langNameSig :: G_sign -> String
langNameSig (G_sign lid _) = language_name lid

-- | Grothendieck signature lists
data G_sign_list = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
  G_sign_list lid [sign] 

-- | Grothendieck extended signatures
data G_ext_sign = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
  G_ext_sign lid sign (Set.Set symbol)

tyconG_ext_sign :: TyCon
tyconG_ext_sign = mkTyCon "Logic.Grothendieck.G_ext_sign"
instance Typeable G_ext_sign where
  typeOf _ = mkTyConApp tyconG_ext_sign []

instance Eq G_ext_sign where
  (G_ext_sign i1 sigma1 sys1) == (G_ext_sign i2 sigma2 sys2) =
     coerce i1 i2 sigma1 == Just sigma2
     && coerce i1 i2 sys1 == Just sys2

instance Show G_ext_sign where
    show (G_ext_sign _ s _) = show s

instance PrettyPrint G_ext_sign where
    printText0 ga (G_ext_sign _ s _) = printText0 ga s

langNameExtSig :: G_ext_sign -> String
langNameExtSig (G_ext_sign lid _ _) = language_name lid

-- | Grothendieck theories
data G_theory = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
  G_theory lid sign [Named sentence]

-- | compute sublogic of a theory
sublogicOfTh :: G_theory -> G_sublogics
sublogicOfTh (G_theory lid sigma sens) =
  let sub = foldr Logic.Logic.join 
                  (min_sublogic_sign lid sigma)
                  (map (min_sublogic_sentence lid . sentence) sens)
   in G_sublogics lid sub

-- | Grothendieck symbols
data G_symbol = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree  =>
  G_symbol lid symbol 

instance Show G_symbol where
  show (G_symbol _ s) = show s

instance Eq G_symbol where
  (G_symbol i1 s1) == (G_symbol i2 s2) =
     coerce i1 i2 s1 == Just s2

-- | Grothendieck symbol lists
data G_symb_items_list = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree  =>
        G_symb_items_list lid [symb_items] 

instance Show G_symb_items_list where
  show (G_symb_items_list _ l) = show l

instance PrettyPrint G_symb_items_list where
    printText0 ga (G_symb_items_list _ l) = 
        fsep $ punctuate comma $ map (printText0 ga) l

instance Eq G_symb_items_list where
  (G_symb_items_list i1 s1) == (G_symb_items_list i2 s2) =
     coerce i1 i2 s1 == Just s2

-- | Grothendieck symbol maps
data G_symb_map_items_list = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree  =>
        G_symb_map_items_list lid [symb_map_items] 

instance Show G_symb_map_items_list where
  show (G_symb_map_items_list _ l) = show l

instance PrettyPrint G_symb_map_items_list where
    printText0 ga (G_symb_map_items_list _ l) = 
        fsep $ punctuate comma $ map (printText0 ga) l

instance Eq G_symb_map_items_list where
  (G_symb_map_items_list i1 s1) == (G_symb_map_items_list i2 s2) =
     coerce i1 i2 s1 == Just s2

-- | Grothendieck diagrams
data G_diagram = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree  =>
        G_diagram lid (Diagram sign morphism) 

-- | Grothendieck sublogics
data G_sublogics = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
        G_sublogics lid sublogics 

tyconG_sublogics :: TyCon
tyconG_sublogics = mkTyCon "Logic.Grothendieck.G_sublogics"
instance Typeable G_sublogics where
  typeOf _ = mkTyConApp tyconG_sublogics []

instance Show G_sublogics where
    show (G_sublogics lid sub) = 
      show lid++"."++head (sublogic_names lid sub)

instance Eq G_sublogics where
    (G_sublogics lid1 l1) == (G_sublogics lid2 l2) =
       coerce lid1 lid2 l1 == Just l2

instance Ord G_sublogics where
    compare (G_sublogics lid1 l1) (G_sublogics lid2 l2) =
     case coerce lid1 lid2 l2 of
       Just l2' -> compare l1 l2' {-if l1==l2' then EQ
                     else if l1 <<= l2' then LT
                     else GT-}
       Nothing -> error "Attempt to compare sublogics of different logics"

-- | Homogeneous Grothendieck signature morphisms
data G_morphism = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
        G_morphism lid morphism

instance Show G_morphism where
    show (G_morphism _ l) = show l


----------------------------------------------------------------
-- Existential types for the logic graph
----------------------------------------------------------------

-- | Existential type for comorphisms
data AnyComorphism = forall cid lid1 sublogics1
        basic_spec1 sentence1 symb_items1 symb_map_items1
        sign1 morphism1 symbol1 raw_symbol1 proof_tree1
        lid2 sublogics2
        basic_spec2 sentence2 symb_items2 symb_map_items2
        sign2 morphism2 symbol2 raw_symbol2 proof_tree2 .
      Comorphism cid 
                 lid1 sublogics1 basic_spec1 sentence1 
                 symb_items1 symb_map_items1
                 sign1 morphism1 symbol1 raw_symbol1 proof_tree1
                 lid2 sublogics2 basic_spec2 sentence2 
                 symb_items2 symb_map_items2
                 sign2 morphism2 symbol2 raw_symbol2 proof_tree2 =>
      Comorphism cid

instance Eq AnyComorphism where
  Comorphism cid1 == Comorphism cid2 =
     language_name cid1 == language_name cid2  
  -- need to be refined, using comorphism translations !!! 

instance Show AnyComorphism where
  show (Comorphism cid) = 
    language_name cid
    ++" : "++language_name (sourceLogic cid)
    ++" -> "++language_name (targetLogic cid)

tyconAnyComorphism :: TyCon
tyconAnyComorphism = mkTyCon "Logic.Grothendieck.AnyComorphism"
instance Typeable AnyComorphism where
  typeOf _ = mkTyConApp tyconAnyComorphism []


-- | Test whether a comporphism is the identity
isIdComorphism :: AnyComorphism -> Bool
isIdComorphism (Comorphism cid) =
  case language_name cid of
    'i':'d':'_':_ -> True
    _ -> False

-- | Compose comorphisms
compComorphism :: Monad m => AnyComorphism -> AnyComorphism -> m AnyComorphism
compComorphism cm1@(Comorphism cid1) cm2@(Comorphism cid2) =
   case coerce (targetLogic cid1) (sourceLogic cid2) (targetSublogic cid1) of
    Just sl1 -> 
      if sl1 <= sourceSublogic cid2
       then case (isIdComorphism cm1,isIdComorphism cm2) of
         (True,_) -> return cm2
         (_,True) -> return cm1
         _ ->  return $ Comorphism (CompComorphism cid1 cid2)
       else fail ("Sublogic mismatch in composition of "++language_name cid1++
		  " and "++language_name cid2)
    Nothing -> fail ("Logic mismatch in composition of "++language_name cid1++
	             " and "++language_name cid2)

-- | Logic graph
data LogicGraph = LogicGraph {
                    logics :: Map.Map String AnyLogic, 
                    comorphisms :: Map.Map String AnyComorphism,
                    inclusions :: Map.Map (String,String) AnyComorphism
                  }

emptyLogicGraph :: LogicGraph
emptyLogicGraph = LogicGraph Map.empty Map.empty Map.empty

-- | find a logic in a logic graph
lookupLogic :: Monad m => String -> String -> LogicGraph -> m AnyLogic
lookupLogic error_prefix logname logicGraph =
    case Map.lookup logname (logics logicGraph) of
    Nothing -> fail (error_prefix++" in LogicGraph logic \""
                      ++logname++"\" unknown")
    Just lid -> return lid

-- | find a comorphism in a logic graph
lookupComorphism :: Monad m => String -> LogicGraph -> m AnyComorphism
lookupComorphism coname logicGraph = do
  let nameList = splitBy ';' coname
  cs <- sequence $ map lookupN nameList
  case cs of
    c:cs1 -> foldM compComorphism c cs1
    _ -> fail ("Illgegal comorphism name: "++coname)
  where 
  lookupN name = 
    case name of
      'i':'d':'_':logic -> do
         l <- maybe (fail ("Cannot find logic "++logic)) return
                 $ Map.lookup logic (logics logicGraph)
         case l of
           Logic lid -> 
            return $ Comorphism $ IdComorphism lid (top_sublogic lid)
      _ -> maybe (fail ("Cannot find logic comorphism "++name)) return
             $ Map.lookup name (comorphisms logicGraph)

-- | auxiliary existential type needed for composition of comorphisms
data AnyComorphismAux lid1 sublogics1
        basic_spec1 sentence1 symb_items1 symb_map_items1
        sign1 morphism1 symbol1 raw_symbol1 proof_tree1
        lid2 sublogics2
        basic_spec2 sentence2 symb_items2 symb_map_items2
        sign2 morphism2 symbol2 raw_symbol2 proof_tree2 = 
        forall cid .
      Comorphism cid 
                 lid1 sublogics1 basic_spec1 sentence1 
                 symb_items1 symb_map_items1
                 sign1 morphism1 symbol1 raw_symbol1 proof_tree1
                 lid2 sublogics2 basic_spec2 sentence2 
                 symb_items2 symb_map_items2
                 sign2 morphism2 symbol2 raw_symbol2 proof_tree2 =>
      ComorphismAux cid lid1 lid2 sign1 morphism2

tyconAnyComorphismAux :: TyCon
tyconAnyComorphismAux = mkTyCon "Logic.Grothendieck.AnyComorphismAux"

instance Typeable (AnyComorphismAux lid1 sublogics1
        basic_spec1 sentence1 symb_items1 symb_map_items1
        sign1 morphism1 symbol1 raw_symbol1 proof_tree1
        lid2 sublogics2
        basic_spec2 sentence2 symb_items2 symb_map_items2
        sign2 morphism2 symbol2 raw_symbol2 proof_tree2)
  where typeOf _ = mkTyConApp tyconG_sign []

instance Show (AnyComorphismAux lid1 sublogics1
        basic_spec1 sentence1 symb_items1 symb_map_items1
        sign1 morphism1 symbol1 raw_symbol1 proof_tree1
        lid2 sublogics2
        basic_spec2 sentence2 symb_items2 symb_map_items2
        sign2 morphism2 symbol2 raw_symbol2 proof_tree2)
  where show _ = "<AnyComorphismAux>"


------------------------------------------------------------------
-- The Grothendieck signature category
------------------------------------------------------------------

-- | Grothendieck signature morphisms
data GMorphism = forall cid lid1 sublogics1
        basic_spec1 sentence1 symb_items1 symb_map_items1
        sign1 morphism1 symbol1 raw_symbol1 proof_tree1
        lid2 sublogics2
        basic_spec2 sentence2 symb_items2 symb_map_items2 
        sign2 morphism2 symbol2 raw_symbol2 proof_tree2 .
      Comorphism cid 
                 lid1 sublogics1 basic_spec1 sentence1 
                 symb_items1 symb_map_items1
                 sign1 morphism1 symbol1 raw_symbol1 proof_tree1
                 lid2 sublogics2 basic_spec2 sentence2 
                 symb_items2 symb_map_items2
                 sign2 morphism2 symbol2 raw_symbol2 proof_tree2 =>
  GMorphism cid sign1 morphism2 

instance Eq GMorphism where
  GMorphism cid1 sigma1 mor1 == GMorphism cid2 sigma2 mor2
     = coerce cid1 cid2 (sigma1, mor1) == Just (sigma2, mor2)

data Grothendieck = Grothendieck deriving Show

instance Language Grothendieck

instance Show GMorphism where
    show (GMorphism cid s m) = show cid ++ "(" ++ show s ++ ")" ++ show m
 
instance PrettyPrint GMorphism where
    printText0 ga (GMorphism cid s m) = 
      ptext (show cid) 
      <+> -- ptext ":" <+> ptext (show (sourceLogic cid)) <+>
      -- ptext "->" <+> ptext (show (targetLogic cid)) <+>
      ptext "(" <+> printText0 ga s <+> ptext ")" 
      $$
      printText0 ga m

instance Category Grothendieck G_sign GMorphism where
  ide _ (G_sign lid sigma) = 
    GMorphism (IdComorphism lid (top_sublogic lid)) sigma (ide lid sigma)
  comp _ 
       (GMorphism r1 sigma1 mor1) 
       (GMorphism r2 _sigma2 mor2) = 
    do let lid1 = sourceLogic r1
           lid2 = targetLogic r1
           lid3 = sourceLogic r2
           lid4 = targetLogic r2
       ComorphismAux r1' _ _ sigma1' mor1' <- 
         (coerce lid2 lid3 $ ComorphismAux r1 lid1 lid2 sigma1 mor1)
       mor1'' <- map_morphism r2 mor1'
       mor <- comp lid4 mor1'' mor2
       return (GMorphism (CompComorphism r1' r2) sigma1' mor)
  dom _ (GMorphism r sigma _mor) = 
    G_sign (sourceLogic r) sigma
  cod _ (GMorphism r _sigma mor) = 
    G_sign lid2 (cod lid2 mor)
    where lid2 = targetLogic r
  legal_obj _ (G_sign lid sigma) = legal_obj lid sigma 
  legal_mor _ (GMorphism r sigma mor) =
    legal_mor lid2 mor && 
    case map_sign r sigma of
      Just (sigma',_) -> sigma' == cod lid2 mor
      Nothing -> False
    where lid2 = targetLogic r


-- | Embedding of homogeneous signature morphisms as Grothendieck sig mors
gEmbed :: G_morphism -> GMorphism
gEmbed (G_morphism lid mor) =
  GMorphism (IdComorphism lid (top_sublogic lid)) (dom lid mor) mor

-- | heterogeneous union of two Grothendieck signatures
--   the left signature determines the result logic
gsigLeftUnion :: LogicGraph -> G_sign -> G_sign -> Result G_sign
gsigLeftUnion lg gsig1@(G_sign lid1 sigma1) gsig2@(G_sign lid2 sigma2) =
  if language_name lid1 == language_name lid2 
     then homogeneousGsigUnion gsig1 gsig2
     else do
      GMorphism incl _ _ <- ginclusion lg 
          (G_sign lid2 (empty_signature lid2))
          (G_sign lid1 (empty_signature lid1))
      let lid1' = targetLogic incl
          lid2' = sourceLogic incl
      sigma1' <- coerce lid1 lid1' sigma1
      sigma2' <- coerce lid2 lid2' sigma2
      (sigma2'',_) <- maybeToMonad "gsigLeftUnion: signature mapping failed" 
                       (map_sign incl sigma2')  -- where to put axioms???
      sigma3 <- signature_union lid1' sigma1' sigma2''
      return (G_sign lid1' sigma3)


-- | homogeneous Union of two Grothendieck signatures
homogeneousGsigUnion :: G_sign -> G_sign -> Result G_sign
homogeneousGsigUnion (G_sign lid1 sigma1) (G_sign lid2 sigma2) = do
  sigma2' <- coerce lid2 lid1 sigma2
  sigma3 <- signature_union lid1 sigma1 sigma2'
  return (G_sign lid1 sigma3)

-- | homogeneous Union of a list of Grothendieck signatures
homogeneousGsigManyUnion :: [G_sign] -> Result G_sign
homogeneousGsigManyUnion [] =
  fail "homogeneous union of emtpy list of signatures"
homogeneousGsigManyUnion (G_sign lid sigma : gsigmas) = do
  sigmas <- let coerce_lid (G_sign lid1 sigma1) = 
                    coerce lid lid1 sigma1
             in sequence (map coerce_lid gsigmas)
  bigSigma <- let sig_union s1 s2 = do
                       s1' <- s1
                       signature_union lid s1' s2
                in foldl sig_union (return sigma) sigmas
  return (G_sign lid bigSigma)


-- | homogeneous Union of a list of morphisms
homogeneousMorManyUnion :: [G_morphism] -> Result G_morphism
homogeneousMorManyUnion [] =
  fail "homogeneous union of emtpy list of morphisms"
homogeneousMorManyUnion (G_morphism lid mor : gmors) = do
  mors <- let coerce_lid (G_morphism lid1 mor1) = 
                    coerce lid lid1 mor1
             in sequence (map coerce_lid gmors)
  bigMor <- let mor_union s1 s2 = do
                       s1' <- s1
                       morphism_union lid s1' s2
                in foldl mor_union (return mor) mors
  return (G_morphism lid bigMor)

-- | inclusion morphism between two Grothendieck signatures
ginclusion :: LogicGraph -> G_sign -> G_sign -> Result GMorphism
ginclusion logicGraph (G_sign lid1 sigma1) (G_sign lid2 sigma2) =
     let ln1 = language_name lid1
         ln2 = language_name lid2 in
     if ln1==ln2 then do
       sigma2' <- rcoerce lid1 lid2 (newPos "s" 0 0) sigma2
       mor <- inclusion lid1 sigma1 sigma2'
       return (GMorphism (IdComorphism lid1 (top_sublogic lid1)) sigma1 mor)
      else case Map.lookup (ln1,ln2) (inclusions logicGraph) of 
           Just (Comorphism i) -> do
	      sigma1' <- rcoerce lid1 (sourceLogic i) (newPos "u" 0 0) sigma1
              (sigma1'',_) <- maybeToResult (newPos "w" 0 0) 
                    "ginclusion: signature map failed" 
                       (map_sign i sigma1')
              sigma2' <- rcoerce lid2 (targetLogic i) (newPos "v" 0 0) sigma2
              mor <- inclusion (targetLogic i) sigma1'' sigma2'
              return (GMorphism i sigma1' mor)
	   Nothing -> Result [Diag FatalError 
			 ("No inclusion from "++ln1++" to "++ln2++" found")
                         (newPos "t" 0 0)] Nothing 
-- | Composition of two Grothendieck signature morphisms 
-- | with itermediate inclusion
compInclusion :: LogicGraph -> GMorphism -> GMorphism -> Result GMorphism
compInclusion lg mor1 mor2 = do
  incl <- ginclusion lg (cod Grothendieck mor1) (dom Grothendieck mor2)
  mor <- maybeToResult nullPos
           "compInclusion: composition falied" $ comp Grothendieck mor1 incl
  maybeToResult nullPos
           "compInclusion: composition falied" $ comp Grothendieck mor mor2


-- | Composition of two Grothendieck signature morphisms 
-- | with itermediate homogeneous inclusion
compHomInclusion :: GMorphism -> GMorphism -> Result GMorphism
compHomInclusion mor1 mor2 = compInclusion emptyLogicGraph mor1 mor2

-- | Translation of a G_l_sentence_list along a GMorphism
translateG_l_sentence_list :: GMorphism -> G_l_sentence_list 
                                 -> Result G_l_sentence_list
translateG_l_sentence_list (GMorphism cid sign1 morphism2)
                           (G_l_sentence_list lid sens) = do
  let tlid = targetLogic cid
  --(sigma2,_) <- map_sign cid sign1
  sens' <- coerce lid (sourceLogic cid) sens
  sens'' <- maybeToResult nullPos "Could not map sentences" 
              $ sequence $ map (mapNamedM (map_sentence cid sign1)) $ sens'
  sens''' <- sequence $ map (mapNamedM (map_sen tlid morphism2)) $ sens''
  return (G_l_sentence_list tlid sens''')

-- | Join two G_l_sentence_list's
joinG_l_sentence_list :: G_l_sentence_list -> G_l_sentence_list
                            -> Maybe G_l_sentence_list
joinG_l_sentence_list (G_l_sentence_list lid1 sens1)
                      (G_l_sentence_list lid2 sens2) = do
  sens2' <- coerce lid1 lid2 sens2
  return (G_l_sentence_list lid1 (sens1++sens2'))

-- | Flatten a list of G_l_sentence_list's
flatG_l_sentence_list :: [G_l_sentence_list] -> Maybe G_l_sentence_list
flatG_l_sentence_list [] = Nothing
flatG_l_sentence_list (gl:gls) = foldM joinG_l_sentence_list gl gls


-- | Find all (composites of) comorphisms starting from a given logic
findComorphismPaths :: LogicGraph ->  G_sublogics -> [AnyComorphism]
findComorphismPaths lg (G_sublogics lid sub) = 
  List.nub $ map fst $ iterateComp (0::Int) [(idc,[idc])]
  where
  idc = Comorphism (IdComorphism lid sub)
  coMors = Map.elems $ comorphisms lg
  -- compute possible compositions, but only up to depth 5
  iterateComp n (l::[(AnyComorphism,[AnyComorphism])]) =
    if n>5 || l==newL then newL else iterateComp (n+1) newL
    where 
    newL = List.nub (l ++ (concat (map extend l)))
    -- extend comorphism list in all directions, but no cylces
    extend (coMor,comps::[AnyComorphism]) =  
       let addCoMor c = 
            case compComorphism coMor c of
              Nothing -> Nothing
              Just c1 -> Just (c1,c:comps)
        in catMaybes $ map addCoMor $ filter (not . (`elem` comps)) $ coMors


------------------------------------------------------------------
-- Provers
------------------------------------------------------------------

-- | Grothendieck sublogics
data G_prover = forall lid sublogics
        basic_spec sentence symb_items symb_map_items
         sign morphism symbol raw_symbol proof_tree .
        Logic lid sublogics
         basic_spec sentence symb_items symb_map_items
          sign morphism symbol raw_symbol proof_tree =>
     G_prover lid (Prover sign sentence proof_tree symbol)
