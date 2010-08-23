{-# LANGUAGE FlexibleInstances, TypeSynonymInstances, UndecidableInstances, MultiParamTypeClasses #-}
{- |
Module      :  $Header$
Description :  Reduce instance for the CalculationSystem class
Copyright   :  (c) Ewaryst Schulz, DFKI Bremen 2010
License     :  GPLv2 or higher

Maintainer  :  Ewaryst.Schulz@dfki.de
Stability   :  experimental
Portability :  non-portable (various glasgow extensions)

Reduce as CalculationSystem
-}

module CSL.ReduceInterpreter where

import Common.ProverTools (missingExecutableInPath)
import Common.Utils (getEnvDef, trimLeft)
import Common.IOS
import Common.ResultT

import CSL.Reduce_Interface ( evalString, exportExp, connectCAS, disconnectCAS
                            , lookupRedShellCmd, Session (..))
import CSL.AS_BASIC_CSL (mkOp, EXPRESSION (..))
import CSL.Parse_AS_Basic (parseResult)
import CSL.Interpreter

-- the process communication interface
import qualified Interfaces.Process as PC

import Control.Monad.Trans (MonadTrans (..), MonadIO (..))
import Control.Monad.State (MonadState (..))

import Data.Maybe
import System.IO (Handle)
import System.Process (ProcessHandle)
import System.Exit (ExitCode)


-- ----------------------------------------------------------------------
-- * Reduce Calculator Instances
-- ----------------------------------------------------------------------

data ReduceInterpreter = ReduceInterpreter { inh :: Handle
                                           , outh ::Handle
                                           , ph :: ProcessHandle }

-- Types for two alternative reduce interpreter
type RedsIO = ResultT (IOS ReduceInterpreter)

type RedcIO = ResultT (IOS PC.CommandState)

instance CalculationSystem RedsIO where
    assign  = redAssign evalRedsString
    clookup = redClookup evalRedsString
    eval = redEval evalRedsString
    check = redCheck evalRedsString
    names = error "ReduceInterpreter as CS: names are unsupported"

instance CalculationSystem RedcIO where
    assign  = redAssign evalRedcString
    clookup = redClookup evalRedcString
    eval = redEval evalRedcString
    check = redCheck evalRedcString
    names = error "ReduceCommandInterpreter as CS: names are unsupported"


instance (MonadState s m, MonadTrans t, Monad (t m)) => MonadState s (t m) where
    get = lift get
    put = lift . put

instance (MonadIO m, MonadTrans t, Monad (t m)) => MonadIO (t m) where
    liftIO = lift . liftIO

-- ----------------------------------------------------------------------
-- * Reduce syntax functions
-- ----------------------------------------------------------------------

printAssignment :: String -> EXPRESSION -> String
printAssignment n e = concat [n, ":=", exportExp e, ";"]

printEvaluation :: EXPRESSION -> String
printEvaluation e = exportExp e ++ ";"

printLookup :: String -> String
printLookup n = n ++ ";"

-- As reduce does not support boolean expressions as first class citizens
-- we encode them in an if-stmt and transform the numeric response back.
printBooleanExpr :: EXPRESSION -> String
printBooleanExpr e = concat ["if ", exportExp e, " then 1 else 0;"]

getBooleanFromExpr :: EXPRESSION -> Bool
getBooleanFromExpr (Int 1 _) = True
getBooleanFromExpr (Int 0 _) = False
getBooleanFromExpr e =
    error $ "getBooleanFromExpr: can't translate expression to boolean: "
              ++ show e

-- ----------------------------------------------------------------------
-- * Generic Communication Interface
-- ----------------------------------------------------------------------

{- |
   The generic interface abstracts over the concrete evaluation function
-}

redAssign :: (CalculationSystem s, MonadResult s) => (String -> s [EXPRESSION]) -> String
          -> EXPRESSION -> s ()
redAssign ef n e = do
  ef $ printAssignment n e
  return ()

redClookup :: (CalculationSystem s, MonadResult s) => (String -> s [EXPRESSION]) -> String
           -> s (Maybe EXPRESSION)
redClookup ef n = do
  [e] <- ef $ printLookup n
  if e == mkOp n [] then return Nothing else return $ Just e

redEval :: (CalculationSystem s, MonadResult s) => (String -> s [EXPRESSION]) -> EXPRESSION
        -> s EXPRESSION
redEval ef e = do
  el <- ef $ printEvaluation e
  if null el
   then error $ "redEval: expression " ++ show e ++ " couldn't be evaluated"
   else return $ head el

redCheck :: (CalculationSystem s, MonadResult s) => (String -> s [EXPRESSION]) -> EXPRESSION
         -> s Bool
redCheck ef e = do
  el <- ef $ printBooleanExpr e
  if null el
   then error $ "redCheck: expression " ++ show e ++ " couldn't be evaluated"
   else return $ getBooleanFromExpr $ head el


-- ----------------------------------------------------------------------
-- * The Standard Communication Interface
-- ----------------------------------------------------------------------

instance Session ReduceInterpreter where
    inp = inh
    outp = outh
    proch = Just . ph

evalRedsString :: String -> RedsIO [EXPRESSION]
evalRedsString s = do
  r <- get
  liftIO $ evalString r s

redsInit :: IO ReduceInterpreter
redsInit = do
  putStr "Connecting CAS.."
  reducecmd <- getEnvDef "HETS_REDUCE" "redcsl"
  -- check that prog exists
  noProg <- missingExecutableInPath reducecmd
  if noProg
   then error $ "Could not find reduce under " ++ reducecmd
   else do
     (inpt, out, _, pid) <- connectCAS reducecmd
     return $ ReduceInterpreter { inh = inpt, outh = out, ph = pid }

redsExit :: ReduceInterpreter -> IO ()
redsExit = disconnectCAS

-- ----------------------------------------------------------------------
-- * An alternative Communication Interface
-- ----------------------------------------------------------------------

-- | A direct way to communicate with Reduce
redcDirect :: PC.CommandState -> String -> IO String
redcDirect cs s = do
  (res, _) <- runIOS cs (PC.call 0.1 s)
  return res

evalRedcString :: String -> RedcIO [EXPRESSION]
evalRedcString s = do
  -- don't need to skip the reducelinenr here, because the Command-Interface
  -- cleans the outpipe before sending (hence removes the reduce line nr)
  lift (PC.call 0.1 s) >>= return . maybeToList . parseResult . trimLeft


-- | init the reduce communication
redcInit :: Int -- ^ Verbosity level
         -> IO PC.CommandState
redcInit v = do
  rc <- lookupRedShellCmd
  case rc of
    Left redcmd ->
        PC.runProgInit redcmd v
              $ PC.send $ "off nat; load redlog; rlset reals; on rounded; "
                    ++ "precision 30;"
    _ -> error "Could not find reduce shell command!"

redcExit :: RedcIO (Maybe ExitCode)
redcExit = lift $ PC.close $ Just "quit;"

