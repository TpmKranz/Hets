{- |
Module      :  $Header$
Copyright   :  (c) Christian Maeder and Uni Bremen 2002-2005
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  maeder@tzi.de
Stability   :  provisional
Portability :  non-portable (MonadState)

analyse alternatives of data types

-}

module HasCASL.DataAna where

import Data.Maybe

import qualified Common.Lib.Map as Map
import qualified Common.Lib.Set as Set
import Common.Id
import Common.Result
import Common.AS_Annotation

import HasCASL.As
import HasCASL.Le
import HasCASL.TypeAna
import HasCASL.AsUtils
import HasCASL.Builtin
import HasCASL.Unify

-- | description of polymorphic data types
data DataPat = DataPat Id [TypeArg] RawKind Type

-- * creating selector equations

mkSelId :: Range -> String -> Int -> Int -> Id
mkSelId p str n m = mkId 
    [Token (str ++ "_" ++ show n ++ "_" ++ show m) p]

mkSelVar :: Int -> Int -> Type -> VarDecl
mkSelVar n m ty = VarDecl (mkSelId (getRange ty) "x" n m) ty  Other nullRange

genTuple :: Int -> Int -> [Selector] -> [VarDecl]
genTuple _ _ [] = [] 
genTuple n m (Select _ ty _ : sels) = 
    mkSelVar n m ty : genTuple n (m + 1) sels

genSelVars :: Int -> [[Selector]]  -> [[VarDecl]]
genSelVars _ [] = []
genSelVars n (ts:sels)  = 
    genTuple n 1 ts : genSelVars (n + 1) sels

makeSelTupleEqs :: DataPat -> Term -> Int -> Int -> [Selector] -> [Named Term]
makeSelTupleEqs dt@(DataPat _ tArgs _ rt) ct n m (Select mi ty p : sels) = 
    let sc = TypeScheme tArgs (getSelType rt p ty) nullRange in
    (case mi of
     Just i -> let
                  vt = QualVar $ mkSelVar n m ty
                  eq = mkEqTerm eqId nullRange (mkApplTerm (mkOpTerm i sc) [ct]) vt
              in [NamedSen ("ga_select_" ++ show i) True eq]
     _ -> [])
    ++ makeSelTupleEqs dt ct n (m + 1) sels
makeSelTupleEqs _ _ _ _ [] = []

makeSelEqs :: DataPat -> Term -> Int -> [[Selector]] -> [Named Term]
makeSelEqs dt ct n (sel:sels) = 
    makeSelTupleEqs dt ct n 1 sel 
    ++ makeSelEqs dt ct (n + 1) sels 
makeSelEqs _ _ _ _ = []

makeAltSelEqs :: DataPat -> AltDefn -> [Named Term]
makeAltSelEqs dt@(DataPat _ args _ rt) (Construct mc ts p sels) = 
    case mc of
    Nothing -> []
    Just c -> let sc = TypeScheme args (getConstrType rt p ts) nullRange 
                  newSc = sc
                  vars = genSelVars 1 sels 
                  as = map ( \ vs -> mkTupleTerm (map QualVar vs) nullRange) vars
                  ct = mkApplTerm (mkOpTerm c newSc) as
              in map (mapNamed (mkForall (map GenTypeVarDecl args
                                  ++ map GenVarDecl (concat vars))))
                 $ makeSelEqs dt ct 1 sels

makeDataSelEqs :: DataEntry -> Type -> [Named Sentence]
makeDataSelEqs (DataEntry _ i _ args rk alts) rt =
    map (mapNamed Formula) $  
    concatMap (makeAltSelEqs $ DataPat i args rk rt) alts

-- * analysis of alternatives

anaAlts :: [DataPat] -> DataPat -> [Alternative] -> TypeEnv -> Result [AltDefn]
anaAlts tys dt alts te = 
    do l <- mapM (anaAlt tys dt te) alts
       Result (checkUniqueness $ catMaybes $ 
               map ( \ (Construct i _ _ _) -> i) l) $ Just ()
       return l

anaAlt :: [DataPat] -> DataPat -> TypeEnv -> Alternative 
       -> Result AltDefn 
anaAlt _ _ te (Subtype ts _) = 
    do l <- mapM ( \ t -> anaStarTypeM t te) ts
       return $ Construct Nothing (map snd l) Partial []
anaAlt tys dt te (Constructor i cs p _) = 
    do newCs <- mapM (anaComps tys dt te) cs
       let sels = map snd newCs
       Result (checkUniqueness $ catMaybes $ 
                map ( \ (Select s _ _) -> s ) $ concat sels) $ Just ()
       return $ Construct (Just i) (map fst newCs) p sels

anaComps :: [DataPat] -> DataPat -> TypeEnv -> [Component]
         -> Result (Type, [Selector]) 
anaComps tys rt te cs =
    do newCs <- mapM (anaComp tys rt te) cs
       return (mkProductType (map fst newCs) nullRange, map snd newCs)

anaComp :: [DataPat] -> DataPat -> TypeEnv -> Component 
        -> Result (Type, Selector)
anaComp tys rt te (Selector s p t _ _) =
    do ct <- anaCompType tys rt t te
       return (ct, Select (Just s) ct p)
anaComp tys rt te (NoSelector t) =
    do ct <- anaCompType tys rt t te
       return  (ct, Select Nothing ct Partial)

anaCompType :: [DataPat] -> DataPat -> Type -> TypeEnv -> Result Type
anaCompType tys (DataPat _ tArgs _ _) t te = do
    (_, ct) <- anaStarTypeM t te
    let ds = unboundTypevars True tArgs ct 
    if null ds then return () else Result ds Nothing
    mapM (checkMonomorphRecursion ct te) tys
    return $ generalize tArgs ct
 
checkMonomorphRecursion :: Type -> TypeEnv -> DataPat -> Result ()
checkMonomorphRecursion t te (DataPat i _ _ rt) = 
    if occursIn (typeMap te) i t then 
       if lesserType te t rt || lesserType te rt t then return ()
       else Result [Diag Error  ("illegal polymorphic recursion" 
                                 ++ expected rt t) $ getRange t] Nothing
    else return ()

occursIn :: TypeMap -> TypeId -> Type -> Bool
occursIn tm i = any (relatedTypeIds tm i) . Set.toList . idsOf (const True)

relatedTypeIds :: TypeMap -> TypeId -> TypeId -> Bool
relatedTypeIds tm i1 i2 = 
    not $ Set.null $ Set.intersection (allRelIds tm i1) $ allRelIds tm i2

allRelIds :: TypeMap -> TypeId -> Set.Set TypeId
allRelIds tm i = Set.union (superIds tm i) $ subIds tm i 

-- | super type ids
superIds :: TypeMap -> Id -> Set.Set Id
superIds tm = supIds tm Set.empty . Set.singleton

subIds :: TypeMap -> Id -> Set.Set Id
subIds tm i = foldr ( \ j s ->
                 if Set.member i $ superIds tm j then
                      Set.insert j s else s) Set.empty $ Map.keys tm

supIds :: TypeMap -> Set.Set Id -> Set.Set Id -> Set.Set Id
supIds tm known new = 
    if Set.null new then known else 
       let more = Set.unions $ map superTypeToId $ 
                  concatMap ( \ i -> superTypes 
                            $ Map.findWithDefault starTypeInfo i tm)
                  $ Set.toList new 
           newKnown = Set.union known new
    in supIds tm newKnown (more Set.\\ newKnown)

superTypeToId :: Type -> Set.Set Id
superTypeToId t = 
    case t of
           TypeName i _ _ -> Set.singleton i
           _ -> Set.empty
