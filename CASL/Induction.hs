{- |
Module      :  $Header$
Description :  Derive induction schemes from sort generation constraints
Copyright   :  (c) Till Mossakowski, Rainer Grabbe and Uni Bremen 2002-2006
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  till@tzi.de
Stability   :  provisional
Portability :  portable

We provide both second-order induction schemes as well as their
instantiation to specific first-order formulas.
-}

module CASL.Induction where

import CASL.AS_Basic_CASL
import CASL.Sign
import CASL.Fold
import Common.AS_Annotation as AS_Anno
import Common.Id
import Common.Result
import Common.DocUtils
import Data.List
import Data.Maybe


-- | derive a second-order induction scheme from a sort generation constraint
-- | the second-order predicate variables are represented as predicate
-- | symbols P[s], where s is a sort
inductionScheme :: Pretty f =>  [Constraint] -> Result (FORMULA f)
inductionScheme constrs =
  induction constrs (map predSubst constrs)
  where sorts = map newSort constrs
        injective = length (nub sorts) == length sorts
        predSubst constr t =
          Predication predSymb [t] nullRange
          where
          predSymb = Qual_pred_name ident typ nullRange
          s = if injective then newSort constr else origSort constr
          ident = Id [mkSimpleId "ga_P"] [s] nullRange
          typ = Pred_type [newSort constr] nullRange

-- | Function for derivation of first-order instances of sort generation
-- | constraints.
-- | Given a list of formulas with a free sorted variable, instantiate the
-- | sort generation constraint for this list of formulas
-- | It is assumed that the (original) sorts of the constraint
-- | match the sorts of the free variables
instantiateSortGen :: Pretty f =>  [Constraint] -> [(FORMULA f,VAR,SORT)]
                        -> Result (FORMULA f)
instantiateSortGen constrs phis =
  induction constrs (map substFormula phis)
  where substFormula (phi,v,_) t = substitute v t phi

-- | substitute a term for a variable in a formula
substitute :: Pretty f =>  VAR -> TERM f -> FORMULA f -> FORMULA f
substitute v t = foldFormula $
 (mapRecord id) { foldQual_var = \ t2 v2 _ _ ->
                  if v == v2 then t else t2
                , foldQuantification = \ t2 q vs p r ->
                  if elem v $ concatMap ( \ (Var_decl l _ _) -> l) vs
                  then t2 else Quantification q vs p r
                }

-- | derive an induction scheme from a sort generation constraint
-- | using substitutions as induction predicates
induction :: Pretty f =>  [Constraint] -> [TERM f -> FORMULA f]
          -> Result (FORMULA f)
induction constrs substs =
 if not (length constrs == length substs)
  then fail "CASL.Induction.induction: argument lists must have equal length"
  else do
   let mkVar i = mkSimpleId ("x_"++show i)
       sortInfo = zip3 constrs substs
                   (zip (map mkVar [1..length constrs]) (map newSort constrs))
       mkConclusion (_,subst,v) =
         Quantification Universal [mkVarDecl v] (subst (mkVarTerm v)) nullRange
       inductionConclusion = mkConj $ map mkConclusion sortInfo
   inductionPremises <- mapM (mkPrems substs) sortInfo
   let inductionPremise = mkConj $ concat inductionPremises
   return $ Implication inductionPremise inductionConclusion True nullRange

-- | construct premise set for the induction scheme
-- | for one sort in the constraint
mkPrems :: Pretty f =>  [TERM f -> FORMULA f]
            -> (Constraint, TERM f -> FORMULA f, (VAR,SORT))
            -> Result [FORMULA f]
mkPrems substs info@(constr,_,_) = mapM (mkPrem substs info) (opSymbs constr)

-- | construct a premise for the induction scheme for one constructor
mkPrem :: Pretty f =>  [TERM f -> FORMULA f]
           -> (Constraint, TERM f -> FORMULA f, (VAR,SORT))
           -> (OP_SYMB,[Int])
           -> Result (FORMULA f)
mkPrem substs (_,subst,_)
       (opSym@(Qual_op_name _ (Op_type _ argTypes _ _) _), idx) =
  return $ if null qVars then phi
            else Quantification Universal (map mkVarDecl qVars) phi nullRange
  where
  vars = map mkVar [1..length argTypes]
  mkVar i = mkSimpleId ("y_"++show i)
  qVars = zip vars argTypes
  phi = if null indHyps then indConcl
           else Implication (mkConj indHyps) indConcl True nullRange
  indConcl = subst (Application opSym (map mkVarTerm qVars) nullRange)
  indHyps = mapMaybe indHyp (zip qVars idx)
  indHyp (v1,i) =
    if i<0 then Nothing -- leave out sorts from outside the constraint
     else Just ((substs!!i) (mkVarTerm v1))
mkPrem _ _ (opSym,_) =
  fail ("CASL.Induction. mkPrems: "
        ++ "unqualified operation symbol occuring in constraint: "
        ++ show opSym)

-- | turn sorted variable into variable delcaration
mkVarDecl :: (VAR,SORT) -> VAR_DECL
mkVarDecl (v,s) = Var_decl [v] s nullRange

-- | turn sorted variable into term
mkVarTerm :: Pretty f =>  (VAR,SORT) -> TERM f
mkVarTerm (v,s) = Qual_var v s nullRange

-- | optimized conjunction
mkConj :: Pretty f =>  [FORMULA f] -> FORMULA f
mkConj [] = False_atom nullRange
mkConj [phi] = phi
mkConj phis = Conjunction phis nullRange


-- !! documentation is missing
generateInductionLemmas :: Pretty f =>  (Sign f e, [Named (FORMULA f)])
                           -> (Sign f e, [Named (FORMULA f)])
generateInductionLemmas (sig,axs) =
   (sig,axs++ {- trace (showDoc (map (mapNamed(simplifySen
                 undefined undefined sig)) inductionAxs) "") -}
        inductionAxs)
   where
   sortGens = filter isSortGen (map sentence axs)
   goals = filter (not . isAxiom) axs
   inductionAxs = fromJust $ maybeResult $
                    generateInductionLemmasAux sortGens goals

-- | determine whether a formula is a sort generation constraint
isSortGen :: FORMULA a -> Bool
isSortGen (Sort_gen_ax _ _) = True
isSortGen _ = False


generateInductionLemmasAux
  :: Pretty f =>  [FORMULA f] -- ^ only Sort_gen_ax of a theory
  -> [AS_Anno.Named (FORMULA f)] -- ^ all goals of a theory
  -> Result ([AS_Anno.Named (FORMULA f)])
-- ^ all the generated induction lemmas
-- and the labels are derived from the goal-names
generateInductionLemmasAux sort_gen_axs goals =
    mapM (\ (cons,formulas) -> do
            formula <- instantiateSortGen cons $
                map (\ (Constraint {newSort = s},(f,varsorts)) ->
                       let vs = findVar s varsorts
                       in  (removeVarsort vs s $ sentence f, vs, s))
                    $ zip cons formulas

            let sName = (if null formulas then id else tail)
                        (foldr ((++) . (++) "_" . senName . fst) "" formulas
                         ++ "_induction")
            return $ AS_Anno.NamedSen { senName = sName, isAxiom = True,
                                        isDef = False, sentence = formula }
         )
         -- returns big list containing tuples of constraints and a matching
         -- combination (list) of goals. The list is from the following type:
         -- ( [Constraint], [ (FORMULA, [(VAR,SORT)]) ] )
         (concat $ map (\ (Sort_gen_ax c _) ->
                          map (\combi -> (c,combi)) $ constraintGoals c)
                       sort_gen_axs)
  where
    findVar s [] = error ("CASL.generateInductionLemmas:\n"
                       ++ "No VAR found of SORT " ++ (show s) ++ "!")
    findVar s ((vl,sl):lst) = if s==sl then vl else findVar s lst
    removeVarsort v s f = case f of
      Quantification Universal varDecls formula rng ->
        let vd' = newVarDecls varDecls
        in  if (null vd') then formula
            else Quantification Universal vd' formula rng
      _ -> f
      where
        newVarDecls = filter (\ (Var_decl vs _ _) -> not $ null vs) .
            map (\ var_decl@(Var_decl vars varsort r) ->
                   if varsort==s
                     then Var_decl (filter (not . (==) v) vars) s r
                     else var_decl)
    uniQuantGoals =
        map (\ goal@NamedSen {sentence = (Quantification _ varDecl _ _)} ->
              (goal, concatVarDecl varDecl))
            $ filter (\ goal -> case (sentence goal) of
                                  Quantification Universal _ _ _ -> True
                                  _ -> False) goals

    -- constraintGoals :: [Constraint] -> [[ (Named FORMULA, [(VAR,SORT)]) ]]
    -- For each constraint we get a list of goals out of uniQuantGoals
    -- which contain the constraint's newSort. Afterwards all combinations
    -- are created.
    constraintGoals cons = combination [] $
              map (\ c -> filter (or . map ((newSort c ==) . snd) . snd)
                                 uniQuantGoals) (sort cons)

{- | A common type list combinator. Given a list of x elements where each
   element contains a list of possibilities for this position. The result
   will be a list of all combinations, where each combination consists of
   x elements.
   Each combination is reversed sorted if the possibilities where sorted before.
   So you have to (map reverse) for resorting.
-}
combination :: [a] -- ^ List of elements each combination will have as preamble.
                   -- Normally this value should be the empty list.
            -> [[a]] -> [[a]]
combination headL [] = [headL]
combination headL (comb:restL) =
    foldr (\ s l -> (combination (s:headL) restL) ++ l)
          [] comb


concatVarDecl :: [VAR_DECL] -> [(VAR,SORT)]
concatVarDecl = foldl (\ vList (Var_decl v s _) ->
                             vList ++ map (\vl -> (vl, s)) v) []
