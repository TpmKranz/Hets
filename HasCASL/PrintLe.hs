{- |
Module      :  $Header$
Description :  pretty printing signatures
Copyright   :  (c) Christian Maeder  and Uni Bremen 2002-2003

Maintainer  :  Christian.Maeder@dfki.de
Stability   :  experimental
Portability :  portable

pretty printing a HasCASL environment
-}

module HasCASL.PrintLe (diffTypeMap, diffType, printMap1) where

import HasCASL.As
import HasCASL.PrintAs
import HasCASL.Le
import HasCASL.Builtin
import HasCASL.ClassAna
import HasCASL.TypeAna

import Common.Doc
import Common.DocUtils
import qualified Data.Map as Map
import qualified Data.Set as Set
import Common.Keywords

import Data.List

instance Pretty ClassInfo where
    pretty (ClassInfo rk ks) = if Set.null ks then colon <+> pretty rk else
        text lessS <+> printList0 (Set.toList ks)

printGenKind :: GenKind -> Doc
printGenKind k = case k of
    Loose -> empty
    Free -> text freeS
    Generated -> text generatedS

instance Pretty TypeDefn where
    pretty td = case td of
        NoTypeDefn -> empty
        PreDatatype -> text "%(data type)%"
        AliasTypeDefn s -> text assignS <+> pretty s
        DatatypeDefn dd -> text "%[" <> pretty dd <> text "]%"

printAltDefn :: AltDefn -> Doc
printAltDefn (Construct mi ts p sels) = case mi of
    Just i -> pretty i <+> fsep (map (parens . semiDs) sels) <> pretty p
    Nothing -> text (typeS ++ sS) <+> ppWithCommas ts

instance Pretty Selector where
    pretty (Select mi t p) =
        (case mi of
        Just i -> pretty i <+> (case p of
                             Partial -> text colonQuMark
                             Total -> colon) <> space
        Nothing -> empty) <> pretty t

instance Pretty TypeInfo where
    pretty (TypeInfo _ ks sups def) =
        fsep $ [colon, printList0 $ Set.toList ks]
             ++ (if Set.null sups then []
                 else [less, printList0 $ Set.toList sups])
             ++ case def of
                  NoTypeDefn -> []
                  _ -> [pretty def]

instance Pretty TypeVarDefn where
    pretty (TypeVarDefn v vk _ i) =
        printVarKind v vk <+> text ("%(var_" ++ shows i ")%")

instance Pretty VarDefn where
    pretty (VarDefn ty) =
        colon <+> pretty ty

instance Pretty ConstrInfo where
    pretty (ConstrInfo i t) =
        pretty i <+> colon <+> pretty t

instance Pretty OpDefn where
    pretty od = case od of
        NoOpDefn b -> text $ "%(" ++ shows b ")%"
        ConstructData _ -> text "%(constructor)%"
        SelectData cs _ -> sep
            [ text "%(selector of constructor(s)"
            , printList0 (Set.toList cs) <> text ")%" ]
        Definition b t ->
            sep [text $ "%[" ++ shows b "=", pretty t <> text "]%" ]

instance Pretty OpInfo where
    pretty o = let l = Set.toList $ opAttrs o in
               fsep $ [pretty (opType o) <> if null l then empty else comma]
                      ++ punctuate comma (map pretty l)
                      ++ [pretty $ opDefn o]

instance Pretty DataEntry where
    pretty (DataEntry im i k args _ alts) =
        printGenKind k <+> keyword typeS <+>
        fsep ([fcat $ pretty i : map (parens . pretty) args
              , defn, cat $ punctuate (space <> bar <> space)
                                      $ map printAltDefn $ Set.toList alts]
             ++ if Map.null im then []
                else [text withS, text (typeS ++ sS), printMap1 im])

instance Pretty Sentence where
    pretty s = case s of
        Formula t -> (case t of
          QuantifiedTerm Universal (_ : _) _ _ -> id
          _ -> addBullet) $ pretty t
        DatatypeSen ls -> vcat (map pretty ls)
        ProgEqSen _ _ pe -> keyword programS <+> pretty pe

instance Pretty Env where
    pretty Env
      { classMap = cm
      , typeMap = tm
      , localTypeVars = tvs
      , assumps = ops
      , localVars = vs
      , sentences = se
      , envDiags=ds } = let
      oops = foldr Map.delete ops $ map fst bList
      otm = diffTypeMap cm tm bTypes
      atm = filterAliases otm
      header m s = keyword $
        if Map.size m < 2 then s else
            if last s == 's' then s ++ "es" else s ++ "s"
      in noPrint (Map.null cm) (header cm classS)
        $+$ printMap0 cm
        $+$ noPrint (Map.null otm) (header otm typeS)
        $+$ printMap0 (Map.map (\ ti -> ti
              { typeDefn = case typeDefn ti of
                  AliasTypeDefn _ -> NoTypeDefn
                  d -> d }) otm)
        $+$ noPrint (Map.null atm) (header atm typeS)
        $+$ printMap0 atm
        $+$ noPrint (Map.null tvs) (header tvs varS)
        $+$ printMap0 tvs
        $+$ printSetMap (keyword opS) space oops
        $+$ noPrint (Map.null vs) (header vs varS)
        $+$ printMap0 vs
        $+$ vcat (map (pretty . fromLabelledSen) $ reverse se)
        $+$ vcat (map pretty $ reverse ds)

printMap0 :: (Pretty a, Ord a, Pretty b) => Map.Map a b -> Doc
printMap0 = printMap id (vcat . punctuate semi) ( \ a b -> fsep $ a : [b])

printMap1 :: (Pretty a, Ord a, Pretty b) => Map.Map a b -> Doc
printMap1 = printMap id vcat ( \ a b -> fsep $ a : mapsto : [b])

instance Pretty Morphism where
  pretty m =
      let tm = typeIdMap m
          fm = funMap m
          -- the types in funs are already mapped
          -- key und value types only differ wrt. partiality
          ds = Map.foldWithKey ( \ (i, _) (j, t) l ->
                (pretty i <+> mapsto <+>
                pretty j <+> colon <+> pretty t) : l)
               [] fm
      in (if Map.null tm then empty
         else keyword (typeS ++ sS) <+> printMap1 tm)
         $+$ (if Map.null fm then empty
             else keyword (opS ++ sS) <+> sepByCommas ds)
         $+$ colon <+> specBraces (pretty $ msource m)
                    $+$ mapsto
                    <+> specBraces (pretty $ mtarget m)

instance Pretty a => Pretty (SymbolType a) where
    pretty t = case t of
      OpAsItemType sc -> pretty sc
      TypeAsItemType k -> pretty k
      ClassAsItemType k -> pretty k

instance Pretty Symbol where
    pretty s = keyword (case symType s of
                            OpAsItemType _ -> opS
                            TypeAsItemType _ -> typeS
                            ClassAsItemType _ -> classS) <+>
                    pretty (symName s) <+> colon <+>
                    pretty (symType s)

instance Pretty RawSymbol where
  pretty rs = case rs of
      AnID i -> pretty i
      AKindedId k i -> printSK k [i] <> pretty i
      AQualId i t -> printSK (symbTypeToKind t) [i] <> pretty i <+> colon
                       <+> pretty t
      ASymbol s -> pretty s

diffTypeMap :: ClassMap -> TypeMap -> TypeMap -> TypeMap
diffTypeMap cm t1 t2 =
    let t = Map.differenceWith (diffType cm) t1 t2
        r = Set.intersection $ Set.union (Map.keysSet t) $ Map.keysSet bTypes
    in Map.map ( \ ti -> ti { superTypes = r $ superTypes ti }) t

-- | compute difference of type infos
diffType :: ClassMap -> TypeInfo -> TypeInfo -> Maybe TypeInfo
diffType cm ti1 ti2 =
    let k1 = otherTypeKinds ti1
        k2 = otherTypeKinds ti2
        ks = Set.filter (\ k -> Set.null $
                  Set.filter (lesserKind cm k) k2) k1
    in if Set.null ks then Nothing else
       Just $ ti1 { otherTypeKinds = ks
                  , superTypes = Set.difference (superTypes ti1) $
                                 superTypes ti2 }

