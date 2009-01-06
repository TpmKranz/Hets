{- |
Module      :  $Id$
Description :  Static analysis of CspCASL
Copyright   :  (c) Andy Gimblett, Liam O'Reilly Markus Roggenbach, Swansea University 2008
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  a.m.gimblett@swansea.ac.uk
Stability   :  provisional
Portability :  portable

Static analysis of CSP-CASL specifications, following "Tool Support
for CSP-CASL", MPhil thesis by Andy Gimblett, 2008.
<http://www.cs.swan.ac.uk/~csandy/mphil/>

-}

module CspCASL.StatAnaCSP where

import qualified Control.Monad as Monad
import qualified Data.Map as Map
import qualified Data.Set as S
-- liam added the following, they should be deleted from imports when
-- liams temp code is removed: Op_name mkSimpleId mkInfix OP_SYMB(..),
-- OP_TYPE(..)
import CASL.AS_Basic_CASL (FORMULA(..), OpKind(..), SORT, TERM(..), VAR,
                           VAR_DECL(..))
import CASL.MixfixParser (emptyMix, Mix(..), makeRules, mkIdSets,
                          resolveFormula, resolveMixfix, unite)
import CASL.Overload (minExpFORMULA, oneExpTerm)
import CASL.Sign
import CASL.Morphism (RawSymbol)
import CASL.StaticAna (allOpIds, allPredIds)
import Common.AS_Annotation
import Common.Result
import Common.GlobalAnnotations
import Common.ConvertGlobalAnnos
import qualified Common.Lib.Rel as Rel
import Common.Id (getRange, Id, simpleIdToId)
import Common.Lib.State
import Common.ExtSign

import CspCASL.AS_CspCASL
import CspCASL.AS_CspCASL_Process
import CspCASL.LocalTop (Obligation(..), unmetObs)
import CspCASL.Print_CspCASL ()
import CspCASL.SignCSP

import qualified Data.Set as Set

basicAnalysisCspCASL :: (CspBasicSpec, CspCASLSign, GlobalAnnos)
        -> Result (CspBasicSpec, ExtSign CspCASLSign Symbol,
                   [Named CspCASLSen])
basicAnalysisCspCASL (cc, sigma, ga) =
    let Result es mga = mergeGlobalAnnos ga $ globAnnos sigma
        (_, accSig) = runState (ana_BASIC_CSP cc) $ case mga of
              Nothing -> sigma
              Just nga -> sigma { globAnnos = nga }
        ds = reverse $ envDiags accSig
        -- Extract process equations only.
        ext = extendedInfo accSig
        ccsents = reverse $ ccSentences ext
        -- Clean signature here
        cleanSig = accSig
                   { extendedInfo = ext { ccSentences = []}}
    in Result (es ++ ds) $
      Just (cc, mkExtSign cleanSig, ccsents)

ana_BASIC_CSP :: CspBasicSpec -> State CspCASLSign ()
ana_BASIC_CSP cc = do checkLocalTops
                      mapM anaChanDecl (channels cc)
                      mapM anaProcItem (proc_items cc)
                      return ()

-- Analysis of local top elements

-- | Check a CspCASL signature for local top elements in its subsort
-- relation.
checkLocalTops :: State CspCASLSign ()
checkLocalTops = do
    sig <- get
    let obs = unmetObs $ Rel.toList $ Rel.transClosure $ sortRel sig
    addDiags (map lteError obs)
    return ()

-- | Add diagnostic error message for every unmet local top element
-- obligation.
lteError :: Obligation SORT -> Diagnosis
lteError (Obligation x y z) = mkDiag Error msg ()
    where msg = ("local top element obligation ("
                 ++ (show x) ++ "<" ++ (show y) ++ "," ++ (show z)
                 ++ ") unfulfilled")

-- Static analysis of channel declarations

-- | Statically analyse a CspCASL channel declaration.
anaChanDecl :: CHANNEL_DECL -> State CspCASLSign ()
anaChanDecl (ChannelDecl chanNames chanSort) = do
    checkSorts [chanSort] -- check channel sort is known
    sig <- get
    let ext = extendedInfo sig
        oldChanMap = chans ext
    newChanMap <- Monad.foldM (anaChannelName chanSort) oldChanMap chanNames
    vds <- gets envDiags
    put sig { extendedInfo = ext { chans = newChanMap }
            , envDiags = vds
            }
    return ()

-- | Statically analyse a CspCASL channel name.
anaChannelName :: SORT -> ChanNameMap -> CHANNEL_NAME ->
                    State CspCASLSign ChanNameMap
anaChannelName s m chanName = do
    sig <- get
    if (show chanName) `S.member` (S.map show (sortSet sig))
      then do let err = "channel name already in use as a sort name"
              addDiags [mkDiag Error err chanName]
              return m
      else case Map.lookup chanName m of
             Nothing -> return (Map.insert chanName s m) -- insert new.
             Just e ->
               if e == s
                 then do let warn = "channel redeclared with same sort"
                         addDiags [mkDiag Warning warn chanName]
                         return m -- already declared with this sort.
                 else do let err = "channel declared with multiple sorts"
                         addDiags [mkDiag Error err chanName]
                         return m

-- Static analysis of process items

-- | Statically analyse a CspCASL process item.
anaProcItem :: PROC_ITEM -> State CspCASLSign ()
anaProcItem procItem =
    case procItem of
      (Proc_Decl name argSorts alpha) -> anaProcDecl name argSorts alpha
      (Proc_Eq parmProcName procTerm) -> anaProcEq parmProcName procTerm

-- Static analysis of process declarations

-- | Statically analyse a CspCASL process declaration.
anaProcDecl :: PROCESS_NAME -> PROC_ARGS -> PROC_ALPHABET
            -> State CspCASLSign ()
anaProcDecl name argSorts (ProcAlphabet commTypes _) = do
    sig <- get
    let ext = extendedInfo sig
        oldProcDecls = procSet ext
    newProcDecls <-
      if name `Map.member` oldProcDecls
        then do -- duplicate process declaration
                let err = "process name declared more than once"
                addDiags [mkDiag Error err name]
                return oldProcDecls
        else do -- new process declation
                checkSorts argSorts -- check argument sorts are known
                -- build alphabet: set of CommType values
                alpha <- Monad.foldM (anaCommType sig) S.empty commTypes
                let profile = (ProcProfile argSorts alpha)
                return (Map.insert name profile oldProcDecls)
    vds <- gets envDiags
    put sig { extendedInfo = ext {procSet = newProcDecls }
            , envDiags = vds
            }
    return ()

-- Static analysis of process equations

-- | Statically analyse a CspCASL process equation.
anaProcEq :: PARM_PROCNAME -> PROCESS -> State CspCASLSign ()
anaProcEq (ParmProcname pn vs) proc = do
    sig <- get
    let ext = extendedInfo sig
        ccsens = ccSentences ext
        procDecls = procSet ext
        prof = pn `Map.lookup` procDecls
    case prof of
         -- Only analyse a process if its name (and thus profile) is known
         Just (ProcProfile procArgs procAlpha) ->
             do  gVars <- anaProcVars pn procArgs vs -- compute global vars
                 (termAlpha, fqProc) <- anaProcTerm proc (Map.fromList gVars) Map.empty
                 checkCommAlphaSub termAlpha procAlpha proc "process equation"
                 -- Save the diags from the checkCommAlphaSub
                 vds <- gets envDiags
                 -- put CspCASL Sentences back in to the state with new sentence
                 put sig {envDiags = vds, extendedInfo =
                          ext { ccSentences =
                                -- BUG - What should the constituent
                                -- alphabet be for this process?
                                -- probably the same as the inner one!
                                (makeNamed ("ProcHugo")
                                               (ProcessEq pn gVars
                                                          Set.empty
                                                          fqProc)):ccsens
                              }
                         }
                 return ()
         Nothing ->
             do addDiags [mkDiag Error "process equation for unknown process" pn]
                return ()
    return ()

-- | Statically analyse a CspCASL process equation's global variable
-- names.
anaProcVars :: PROCESS_NAME -> [SORT] -> [VAR] -> State CspCASLSign ProcVarList
anaProcVars pn ss vs = do
    case (compare (length ss) (length vs)) of
       LT -> do addDiags [mkDiag Error "too many process arguments" pn]
                return []
       GT -> do addDiags [mkDiag Error "not enough process arguments" pn]
                return []
       EQ -> Monad.foldM anaProcVar [] (zip vs ss)

-- | Statically analyse a CspCASL process-global variable name.
anaProcVar :: ProcVarList -> (VAR, SORT) -> State CspCASLSign ProcVarList
anaProcVar old (v, s) = do
    if v `elem` (map fst old)
       then do addDiags [mkDiag Error "process argument declared more than once" v]
               return old
       else return (old ++ [(v, s)])

-- Static analysis of process terms

-- BUG in fucntion below
-- not returing FQProcesses
-- | Statically analyse a CspCASL process term.
--   The process that is returned is a fully qualified process.
anaProcTerm :: PROCESS -> ProcVarMap -> ProcVarMap ->
               State CspCASLSign (CommAlpha, PROCESS)
anaProcTerm proc gVars lVars = case proc of
    NamedProcess name args range ->
        do addDiags [mkDiag Debug "Named process" proc]
           al <- anaNamedProc proc name args (lVars `Map.union` gVars)
           return (al,
                   FQProcess (NamedProcess name args range) al range)
    Skip range ->
        do addDiags [mkDiag Debug "Skip" proc]
           return (S.empty,
                   FQProcess (Skip range) S.empty range)
    Stop range ->
        do addDiags [mkDiag Debug "Stop" proc]
           return (S.empty,
                   FQProcess (Stop range) S.empty range)
    Div range ->
        do addDiags [mkDiag Debug "Div" proc]
           return (S.empty,
                   FQProcess (Div range) S.empty range)
    Run es range ->
        do addDiags [mkDiag Debug "Run" proc]
           comms <- anaEventSet es
           return (comms,
                   FQProcess (Run es range) comms range)
    Chaos es range ->
        do addDiags [mkDiag Debug "Chaos" proc]
           comms <- anaEventSet es
           return (comms,
                   FQProcess (Chaos es range) comms range)
    PrefixProcess e p range ->
        do addDiags [mkDiag Debug "Prefix" proc]
           (evComms, rcvMap, fqEvent) <- anaEvent e (lVars `Map.union` gVars)
           (comms, pFQTerm) <- anaProcTerm p gVars (rcvMap `Map.union` lVars)
           return (comms `S.union` evComms,
                   FQProcess (PrefixProcess fqEvent pFQTerm range) (comms `S.union` evComms) range)
    InternalPrefixProcess v s p range ->
        do addDiags [mkDiag Debug "Internal prefix" proc]
           checkSorts [s] -- check sort is known
           (comms, pFQTerm) <- anaProcTerm p gVars (Map.insert v s lVars)
           return (S.insert (CommTypeSort s) comms,
                   FQProcess (InternalPrefixProcess v s pFQTerm range) (S.insert (CommTypeSort s) comms) range)
    ExternalPrefixProcess v s p range ->
        do addDiags [mkDiag Debug "External prefix" proc]
           checkSorts [s] -- check sort is known
           (comms, pFQTerm) <- anaProcTerm p gVars (Map.insert v s lVars)
           return (S.insert (CommTypeSort s) comms,
                   FQProcess (ExternalPrefixProcess v s pFQTerm range) (S.insert (CommTypeSort s) comms) range)
    Sequential p q range ->
        do addDiags [mkDiag Debug "Sequential" proc]
           (pComms, pFQTerm) <- anaProcTerm p gVars lVars
           (qComms, qFQTerm) <- anaProcTerm q gVars Map.empty
           return (pComms `S.union` qComms,
                   FQProcess (Sequential pFQTerm qFQTerm range) (pComms `S.union` qComms) range)
    InternalChoice p q range ->
        do addDiags [mkDiag Debug "InternalChoice" proc]
           (pComms, pFQTerm) <- anaProcTerm p gVars lVars
           (qComms, qFQTerm) <- anaProcTerm q gVars lVars
           return (pComms `S.union` qComms,
                   FQProcess (InternalChoice pFQTerm qFQTerm range) (pComms `S.union` qComms) range)
    ExternalChoice p q range ->
        do addDiags [mkDiag Debug "ExternalChoice" proc]
           (pComms, pFQTerm) <- anaProcTerm p gVars lVars
           (qComms, qFQTerm) <- anaProcTerm q gVars lVars
           return (pComms `S.union` qComms,
                   FQProcess (ExternalChoice pFQTerm qFQTerm range) (pComms `S.union` qComms) range)
    Interleaving p q range ->
        do addDiags [mkDiag Debug "Interleaving" proc]
           (pComms, pFQTerm) <- anaProcTerm p gVars lVars
           (qComms, qFQTerm) <- anaProcTerm q gVars lVars
           return (pComms `S.union` qComms,
                   FQProcess (Interleaving pFQTerm qFQTerm range) (pComms `S.union` qComms) range)
    SynchronousParallel p q range ->
        do addDiags [mkDiag Debug "Synchronous" proc]
           (pComms, pFQTerm) <- anaProcTerm p gVars lVars
           (qComms, qFQTerm) <- anaProcTerm q gVars lVars
           return (pComms `S.union` qComms,
                   FQProcess (SynchronousParallel pFQTerm qFQTerm range) (pComms `S.union` qComms) range)
    GeneralisedParallel p es q range ->
        do addDiags [mkDiag Debug "Generalised parallel" proc]
           (pComms, pFQTerm) <- anaProcTerm p gVars lVars
           synComms <- anaEventSet es
           (qComms, qFQTerm) <- anaProcTerm q gVars lVars
           return (S.unions [pComms, qComms, synComms],
                   FQProcess (GeneralisedParallel pFQTerm es qFQTerm range) (S.unions [pComms, qComms, synComms]) range)
    AlphabetisedParallel p esp esq q range ->
        do addDiags [mkDiag Debug "Alphabetised parallel" proc]
           (pComms, pFQTerm) <- anaProcTerm p gVars lVars
           pSynComms <- anaEventSet esp
           checkCommAlphaSub pSynComms pComms proc
                                 "alphabetised parallel, left"
           qSynComms <- anaEventSet esq
           (qComms, qFQTerm) <- anaProcTerm q gVars lVars
           checkCommAlphaSub qSynComms qComms proc
                                 "alphabetised parallel, right"
           return (pComms `S.union` qComms,
                   FQProcess (AlphabetisedParallel pFQTerm esp esq qFQTerm range) (pComms `S.union` qComms) range)
    Hiding p es range ->
        do addDiags [mkDiag Debug "Hiding" proc]
           (pComms, pFQTerm) <- anaProcTerm p gVars lVars
           hidComms <- anaEventSet es
           return (pComms `S.union` hidComms,
                   FQProcess (Hiding pFQTerm es range) (pComms `S.union` hidComms) range)
    RenamingProcess p r range ->
        do addDiags [mkDiag Debug "Renaming" proc]
           (pComms, pFQTerm) <- anaProcTerm p gVars lVars
           renAlpha <- anaRenaming r
           return (pComms `S.union` renAlpha,
                   FQProcess (RenamingProcess pFQTerm r range) (pComms `S.union` renAlpha) range)
    ConditionalProcess f p q range ->
        do addDiags [mkDiag Debug "Conditional" proc]
           (pComms, pFQTerm) <- anaProcTerm p gVars lVars
           (qComms, qFQTerm) <- anaProcTerm q gVars lVars
           -- mfs is the fully qualified formula version of f
           mfs <- anaFormulaCspCASL (gVars `Map.union` lVars) f
           let fFQ = case mfs of
                       Nothing -> f -- use olf formula as the fully qualified version
                       Just fs -> fs -- use the real fully qualified formula
           let fComms = case mfs of
                          Nothing -> S.empty
                          Just fs -> formulaComms fs
           let newAlpha = S.unions [pComms, qComms, fComms]
           let fqProc = FQProcess (ConditionalProcess
                                   (fFQ) pFQTerm qFQTerm range)
                        newAlpha range
           return (newAlpha, fqProc)

-- | Statically analyse a CspCASL "named process" term.
anaNamedProc :: PROCESS -> PROCESS_NAME -> [TERM ()] -> ProcVarMap ->
                State CspCASLSign CommAlpha
anaNamedProc proc pn terms procVars = do
    sig <- get
    let ext = extendedInfo sig
        procDecls = procSet ext
        prof = pn `Map.lookup` procDecls
    case prof of
      Just (ProcProfile varSorts permAlpha) ->
        if (length terms) == (length varSorts)
          then do mapM (anaNamedProcTerm procVars) (zip terms varSorts)
                  return permAlpha
          else do let err = "wrong number of arguments in named process"
                  addDiags [mkDiag Error err proc]
                  return S.empty
      Nothing ->
        do addDiags [mkDiag Error "unknown process name" proc]
           return S.empty

-- | Statically analysis a CASL term occurring in a CspCASL "named
-- process" term.
anaNamedProcTerm :: ProcVarMap -> ((TERM ()), SORT) -> State CspCASLSign ()
anaNamedProcTerm pm (t, expSort) = do
    mt <- anaTermCspCASL pm t
    case mt of
      Nothing -> return () -- CASL term analysis failed
      (Just at) -> do ccTermCast at expSort -- attempt cast; don't need result
                      return ()

-- Static analysis of event sets and communication types

-- | Statically analyse a CspCASL event set.
anaEventSet :: EVENT_SET -> State CspCASLSign CommAlpha
anaEventSet (EventSet es _) = do
  sig <- get
  comms <- Monad.foldM (anaCommType sig) S.empty es
  vds <- gets envDiags
  put sig { envDiags = vds }
  return comms

-- | Statically analyse a CspCASL communication type.
anaCommType :: CspCASLSign -> CommAlpha -> COMM_TYPE ->
               State CspCASLSign CommAlpha
anaCommType sig alpha ct =
    if ctSort `S.member` (sortSet sig)
      then -- ct is a sort name; insert sort into alpha
        do return (S.insert (CommTypeSort ctSort) alpha)
      else -- ct not a sort name, so should be a channel name
        case Map.lookup ct (chans $ extendedInfo sig) of
          Just s -> -- ct is a channel name; insert typed chan name into alpha
                    return (S.insert (mkTypedChan ct s) alpha)
          Nothing -> do let err = "not a sort or channel name"
                        addDiags [mkDiag Error err ct]
                        return alpha
        where ctSort = simpleIdToId ct
              mkTypedChan c s = CommTypeChan $ TypedChanName c s

-- Static analysis of events

-- | Statically analyse a CspCASL event. Returns a constituent
--   communication alphabet of the event, mapping for any new
--   locally bound variables and a fully qualified version of the event.
anaEvent :: EVENT -> ProcVarMap -> State CspCASLSign (CommAlpha, ProcVarMap, EVENT)
anaEvent e vars = case e of
                    TermEvent t r ->
                        do (alpha, newVars, fqTerm) <- anaTermEvent t vars
                           return (alpha, newVars, TermEvent fqTerm r)
                    ChanSend c t r ->
                        -- BUG - not returning a fully qualified event
                        do (alpha, newVars, fqTerm) <- anaChanSend c t vars
                           return (alpha, newVars, ChanSend c fqTerm r)
                    ChanNonDetSend c v s r ->
                        -- BUG - not returning a fully qualified event
                        do (alpha, newVars) <- anaChanBinding c v s
                           return (alpha, newVars, ChanNonDetSend c v s r)
                    ChanRecv c v s r ->
                        -- BUG - not returning a fully qualified event
                        do (alpha, newVars) <- anaChanBinding c v s
                           return (alpha, newVars, ChanRecv c v s r)

-- | Statically analyse a CspCASL term event. Returns a constituent
--   communication alphabet of the event and a mapping for any new
--   locally bound variables and the fully qualified version of the
--   term.
anaTermEvent :: (TERM ()) -> ProcVarMap ->
                State CspCASLSign (CommAlpha, ProcVarMap, TERM ())
anaTermEvent t vars = do
  mt <- anaTermCspCASL vars t
  let (alpha, t') = case mt of
                      -- return the alphabet and the fully qualified term
                      Just at -> ([(CommTypeSort (sortOfTerm at))], at)
                      -- return the empty alphabet and the original term
                      Nothing -> ([], t)
  return (S.fromList alpha, Map.empty, t')

-- | Statically analyse a CspCASL channel send event. Returns a constituent
--   communication alphabet of the event and a mapping for any new
--   locally bound variables and the fully qualified version of the
--   term.
anaChanSend :: CHANNEL_NAME -> (TERM ()) -> ProcVarMap ->
                State CspCASLSign (CommAlpha, ProcVarMap, TERM ())
anaChanSend c t vars = do
  sig <- get
  let ext = extendedInfo sig
  case c `Map.lookup` (chans ext) of
    Nothing -> do
      addDiags [mkDiag Error "unknown channel" c]
      return (S.empty, Map.empty, t)
    Just chanSort -> do
      mt <- anaTermCspCASL vars t
      case mt of
        Nothing -> -- CASL analysis failed
                   -- Use old term as the fully qualified term
                   return (S.empty, Map.empty, t)
        (Just at) ->
            do mc <- ccTermCast at chanSort
               case mc of
                 Nothing -> -- cast failed
                            -- Use old term as the fully qualified term
                            return (S.empty, Map.empty, t)
                 (Just ct) ->
                     do let castSort = sortOfTerm ct
                            alpha = [CommTypeSort castSort
                                    ,CommTypeChan $ TypedChanName c castSort
                                    ]
                        -- Use the real fully qualified term
                        return (S.fromList alpha, Map.empty, ct)

-- | Statically analyse a CspCASL "binding" channel event (which is
-- either a channel nondeterministic send event or a channel receive
-- event).
anaChanBinding :: CHANNEL_NAME -> VAR -> SORT ->
                   State CspCASLSign (CommAlpha, ProcVarMap)
anaChanBinding c v s = do
  checkSorts [s] -- check sort is known
  sig <- get
  let ext = extendedInfo sig
  case c `Map.lookup` (chans ext) of
    Nothing -> do
      addDiags [mkDiag Error "unknown channel" c]
      return (S.empty, Map.empty)
    Just chanSort -> do
      if s `S.member` (chanSort `S.insert` (subsorts chanSort))
        then do let alpha = [CommTypeSort s
                            ,CommTypeChan (TypedChanName c s)]
                let binding = [(v, s)]
                return (S.fromList alpha, Map.fromList binding)
        else do let err = "sort not a subsort of channel's sort"
                addDiags [mkDiag Error err s]
                return (S.empty, Map.empty)
            where subsorts = Rel.predecessors (sortRel sig)

-- Static analysis of renaming and renaming items

-- | Statically analyse a CspCASL renaming.
anaRenaming :: RENAMING -> State CspCASLSign CommAlpha
anaRenaming r = do al <- Monad.foldM anaRenamingItem S.empty r
                   return al

-- | Statically analyse a CspCASL renaming item.
anaRenamingItem :: CommAlpha -> Id -> State CspCASLSign CommAlpha
anaRenamingItem inAl ri = do
    totOps <- getUnaryOpsById ri Total
    if (not $ S.null totOps)
      then return (inAl `S.union` totOps)
      else do parOps <- getUnaryOpsById ri Partial
              if (not $ S.null parOps)
                then return (inAl `S.union` parOps)
                else do preds <- getBinPredsById ri
                        if (not $ S.null preds)
                          then return (inAl `S.union` preds)
                          else do let err = ("renaming item not a binary " ++
                                             "operation or predicate name")
                                  addDiags [mkDiag Error err ri]
                                  return inAl

-- | Given a CASL identifier and a `function kind' (total or partial),
-- find all unary operations of that kind with that name in the CASL
-- signature, and return a set of corresponding communication types
-- for those operations.
getUnaryOpsById :: Id -> OpKind -> State CspCASLSign (S.Set CommType)
getUnaryOpsById ri kind = do
    sig <- get
    let opsWithId = Map.findWithDefault S.empty ri (opMap sig)
        binOpsKind = S.filter (isBin kind) opsWithId
        cts = S.map CommTypeSort $ S.fold opSorts S.empty binOpsKind
    return cts
      where isBin k ot = (k == opKind ot) && (1 == (length (opArgs ot)))
            opSorts o inS = inS `S.union` (S.fromList ((opArgs o) ++ [opRes o]))

-- | Given a CASL identifier find all binary predicates with that name
-- in the CASL signature, and return a set of corresponding
-- communication types for those predicates.
getBinPredsById :: Id -> State CspCASLSign (S.Set CommType)
getBinPredsById ri = do
    sig <- get
    let predsWithId = Map.findWithDefault S.empty ri (predMap sig)
        binPreds = S.filter isBin predsWithId
        cts = S.map CommTypeSort $ S.fold predSorts S.empty binPreds
    return cts
      where isBin ot = (2 == (length (predArgs ot)))
            predSorts p inS = inS `S.union` (S.fromList (predArgs p))

-- | Given two CspCASL communication alphabets, check that the first's
-- subsort closure is a subset of the second's subsort closure.
checkCommAlphaSub :: CommAlpha -> CommAlpha -> PROCESS -> String ->
                     State CspCASLSign ()
checkCommAlphaSub sub super proc context = do
  sig <- get
  let extras = ((closeCspCommAlpha sig sub) `S.difference`
                (closeCspCommAlpha sig super))
  if S.null extras
    then do return ()
    else do let err = ("Communication alphabet subset violations (" ++
                       context ++ "): " ++ (show $ S.toList extras))
            addDiags [mkDiag Error err proc]
            return ()

-- Static analysis of CASL terms occurring in CspCASL process terms.

-- | Statically analyse a CASL term appearing in a CspCASL process;
-- any in-scope process variables are added to the signature before
-- performing the analysis.
anaTermCspCASL :: ProcVarMap -> (TERM ()) ->
                  State CspCASLSign (Maybe (TERM ()))
anaTermCspCASL pm t = do
    sig <- get
    let newVars = Map.union pm (varMap sig)
        sigext = sig { varMap = newVars }
        Result ds mt = anaTermCspCASL' sigext t
    addDiags ds
    return mt

-- | Statically analyse a CASL term in the context of a CspCASL
-- signature.  If successful, returns a fully-qualified term.
anaTermCspCASL' :: CspCASLSign -> TERM () -> Result (TERM ())
anaTermCspCASL' sig trm = do
    let allIds = unite [mkIdSets (allOpIds sig) $ allPredIds sig]
        ga = globAnnos sig
        mix = emptyMix { mixRules = makeRules ga allIds }
    resT <- resolveMixfix (putParen mix) (mixResolve mix)
                 ga (mixRules mix) trm
    oneExpTerm (const return) sig resT

-- | Attempt to cast a CASL term to a particular CASL sort.
ccTermCast :: (TERM ()) -> SORT -> State CspCASLSign (Maybe (TERM ()))
ccTermCast t cSort =
    if termSort == (cSort)
      then return (Just t)
      else do sig <- get
              if Rel.member termSort cSort (sortRel sig)
                then do let err = "upcast term to " ++ (show cSort)
                        addDiags [mkDiag Debug err t]
                        return (Just (Sorted_term t cSort (getRange t)))
                else if Rel.member cSort termSort (sortRel sig)
                       then do let err = "downcast term to " ++ (show cSort)
                               addDiags [mkDiag Debug err t]
                               return (Just (Cast t cSort (getRange t)))
                       else do let err = "can't cast term to sort " ++
                                           (show cSort)
                               addDiags [mkDiag Error err t]
                               return Nothing
        where termSort = (sortOfTerm t)

-- Static analysis of CASL formulae occurring in CspCASL process
-- terms.

-- | Statically analyse a CASL formula appearing in a CspCASL process;
-- any in-scope process variables are added to the signature before
-- performing the analysis.
anaFormulaCspCASL :: ProcVarMap -> (FORMULA ()) ->
                     State CspCASLSign (Maybe (FORMULA ()))
anaFormulaCspCASL pm f = do
    addDiags [mkDiag Debug "anaFormulaCspCASL" f]
    sig <- get
    let newVars = Map.union pm (varMap sig)
        sigext = sig { varMap = newVars }
        Result ds mt = anaFormulaCspCASL' sigext f
    addDiags ds
    return mt

-- | Statically analyse a CASL formula in the context of a CspCASL
-- signature.  If successful, returns a fully-qualified formula.
anaFormulaCspCASL' :: CspCASLSign -> FORMULA () -> Result (FORMULA ())
anaFormulaCspCASL' sig frm = do
    let allIds = unite [mkIdSets (allOpIds sig) $ allPredIds sig]
        ga = globAnnos sig
        mix = emptyMix { mixRules = makeRules ga allIds }
    resF <- resolveFormula (putParen mix) (mixResolve mix) ga (mixRules mix) frm
    minExpFORMULA (const return) sig resF

-- | Compute the communication alphabet arising from a formula
-- occurring in a CspCASL process term.
formulaComms :: (FORMULA ()) -> CommAlpha
formulaComms f = case f of
    Quantification _ varDecls f' _ ->
        (formulaComms f') `S.union` S.fromList vdSorts
            where vdSorts = (map (CommTypeSort . vdSort) varDecls)
                  vdSort (Var_decl _ s _) = s
    Conjunction fs _ -> S.unions (map formulaComms fs)
    Disjunction fs _ -> S.unions (map formulaComms fs)
    Implication f1 f2 _ _ -> (formulaComms f1) `S.union` (formulaComms f2)
    Equivalence f1 f2 _ -> (formulaComms f1) `S.union` (formulaComms f2)
    Negation f' _ -> formulaComms f'
    True_atom _ -> S.empty
    False_atom _ -> S.empty
    Predication _ _ _ -> S.empty
    Definedness t _ -> S.singleton (CommTypeSort (sortOfTerm t))
    Existl_equation t1 t2 _ -> S.fromList [CommTypeSort (sortOfTerm t1),
                                           CommTypeSort (sortOfTerm t2)]
    Strong_equation t1 t2 _ -> S.fromList [CommTypeSort (sortOfTerm t1),
                                           CommTypeSort (sortOfTerm t2)]
    Membership t s _ -> S.fromList [CommTypeSort (sortOfTerm t),
                                    CommTypeSort s]
    Mixfix_formula t -> S.singleton (CommTypeSort (sortOfTerm t))
    Unparsed_formula _ _ -> S.empty
    Sort_gen_ax _ _ -> S.empty
    ExtFORMULA _ -> S.empty
