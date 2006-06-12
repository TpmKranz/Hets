{- |
Module      :  $Header$
Description :  Help functions for all automatic theorem provers.
Copyright   :  (c) Rainer Grabbe
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  rainer25@tzi.de
Stability   :  provisional
Portability :  needs POSIX

Functions for parsing and mapping MathServ output.

-}

module SPASS.MathServParsing where

import Logic.Prover

import SPASS.Sign
import SPASS.MathServCommunication

import qualified Common.AS_Annotation as AS_Anno

import Network.URI
import Network.Service
import Org.Xmlsoap.Schemas.Soap.Envelope as ENV

import Text.XML.HXT.Aliases
import Text.XML.HXT.Parser hiding (when)
import Text.XML.HXT.XPath
import Text.Regex

import Data.List
import Data.Maybe

import GUI.GenericATP (guiDefaultTimeLimit)
import GUI.GenericATPState

-- * MathServ Interfacing Code

makeEndPoint :: String -> Maybe HTTPTransport
makeEndPoint uriStr = maybe Nothing
                            (\ uri -> Just $ HTTPTransport
                                      { httpEndpoint = uri
                                      , httpSOAPAction = Just nullURI})
                            (parseURI uriStr)

{- |
  Sends a problem in TPTP format to MathServ using a given time limit.
  Either MathServ output is returned or a simple error message (no XML).
-}
callMathServ :: String -- ^ MathServ Service name
             -> String -- ^ SOAP operation name
             -> String -- ^ Problem to prove in TPTP format
             -> Int -- ^ Time limit
             -> Maybe String -- ^ extra options
             -> IO String -- ^ MathServ output or error message
callMathServ service operation problem timeout xopts =
    do
       maybe (do
                return "Could not start MathServ.")
             (\ endPoint -> do
                 (res::Either SimpleFault MathServOutput)
                    <- soapCall endPoint $
                       mkProveProblem xopts service operation problem timeout
                 case res of
                  Left mErr -> do
                    return $ show mErr
                  Right resp -> do
                    return $ getResponse resp
             )
             (makeEndPoint $
                "http://"++server++':':port++"/axis/services/"++service)
    where
    -- server data
        server = "denebola.informatik.uni-bremen.de"
        port = "8080"

{- |
  Verifies if the used prover was SPASS.This is done by parsing the prover 
  output.
-}
isSPASSOutput :: [String] -- ^ the prover output (maybe SPASS)
              -> Bool
isSPASSOutput out =
    isJust $ matchRegex re_spass $ unlines out
    where
      re_spass = mkRegex "SPASS V.*$"

{- |
  Reads and parses the output of SPASS. The goal status will be updated (if 
  possible), used axioms will be filtered and added.
-}
parseSPASSOutput :: [String] -- ^ SPASS output, beginning with result line
                 -> (Maybe GoalStatus, [String])
                 -> (Maybe GoalStatus, [String])
                    -- ^ (current goal status, currently used axioms)
parseSPASSOutput [] result = result
parseSPASSOutput (line:ls) (res, usedAxs) =
    if null ls then (res', usedAxs') else parseSPASSOutput ls (res', usedAxs')

    where
      resultMatch = matchRegex re_sb line
      res' = maybe res createGoalStatus resultMatch
      createGoalStatus resMatch
        | elem proved resMatch = Just $ Proved Nothing
        | elem disproved resMatch = Just Disproved
        | elem timelimit resMatch = Just Open
        | otherwise = res
      usedAxsMatch = matchRegex re_ua line
      usedAxs' = if isJust usedAxsMatch
                 then (words $ head $ fromJust usedAxsMatch) else usedAxs

      re_sb = mkRegex "SPASS beiseite: (.*)$"
      re_ua = mkRegex "Formulae used in the proof.*:(.*)$"
      proved = "Proof found."
      disproved = "Completion found."
      timelimit = "Ran out of time."

{- |
  Parses the MathServ output.
-}
parseMathServOut :: String -- ^ MathServ output or error messages
                 -> GenericConfig () -- ^ configuration to use
                 -> AS_Anno.Named SPTerm -- ^ goal to prove
                 -> String -- ^ prover name
                 -> IO (ATPRetval, GenericConfig ()) 
                 -- ^ (retval, configuration with proof status and
                 --    complete output)
parseMathServOut mathServOut cfg nGoal prName = do
    mtrees <- parseXML mathServOut
    let rdfTree = maybe emptyRoot head mtrees
        res = mapToGoalStatus $ getXTextValue $ getXPath resultXPath rdfTree
        output = maybe (lines mathServOut) (lines . unTab) $
                       getXTextValue $ getXPath outputXPath rdfTree
        timeout = isJust $ matchRegex re_timeout $ unlines output

    -- get some more infos if SPASS was used
        (res', usedAxs) = if isSPASSOutput output
                             then parseSPASSOutput output (res, [])
                             -- the goal itself was used as an axiom
                             else (res, [AS_Anno.senName nGoal])
        (atpErr, retval) = proof_stat nGoal res' usedAxs timeout defaultPrStat
    return (atpErr,
            cfg{proof_status = retval,
                resultOutput = output})
    where
      tLimit = maybe (guiDefaultTimeLimit) id $ timeLimit cfg
      defaultPrStat = defaultProof_status nGoal prName tLimit
      -- replace tabulators with each 8 spaces
      unTab = foldr (\ch li ->
                        if ch == '\x9' then "        "++li
                                       else ch:li) ""
      outputXPath = "/mw:*[local-name()='FoAtpResult']/mw:*[local-"
                     ++ "name()='output']/text()"
      resultXPath = "/mw:*[local-name()='FoAtpResult']/mw:*[local-"
                     ++ "name()='status']/attribute::rdf:*/text()"
      re_timeout = mkRegex "Terminated by signal."

{- |
  Maps the status message from MathServ results to GoalStatus.
  RegExp are used.
-}
mapToGoalStatus :: Maybe String -- ^ MathServ output
                -> Maybe GoalStatus -- ^ final parsed goal status
mapToGoalStatus stat = case stat of
    Nothing -> Nothing
    Just st -> if isJust $ matchRegex re_theorem st then Just $ Proved Nothing
                 else if isJust $ matchRegex re_counter st then Just Disproved
                   else Just Open
    where
      re_theorem = mkRegex "Theorem$"
      re_counter = mkRegex "Counter$"

{- |
  Helper function. Given a one-elemented [XmlTree], containing an XText element
  in first node, the function returns value of this XText element, if existing.
-}
getXTextValue :: XmlTrees -- ^ XmlTrees to parse
              -> Maybe String -- ^ value of XText element
getXTextValue xmltrees = case xmltrees of
    [] -> Nothing
    xt -> let firstNode = getNode $ head xt
          in  if isXTextNode firstNode
                 then (\(XText s) -> Just s) firstNode
                 else Nothing

{- |
  Default proof status. Contains the goal name, prover name
  and the time limit option used by MathServ.
-}
defaultProof_status :: AS_Anno.Named SPTerm -- ^ goal to prove
                    -> String -- ^ prover name
                    -> Int -- ^ time limit
                    -> Proof_status ()
defaultProof_status nGoal prName tl =
  (openProof_status (AS_Anno.senName nGoal)
                    prName ())
  {tacticScript = Tactic_script $ show tl}


{- |
  Returns the value of a prover run used in GUI (Success, Error or
  TLimitExceeded), and the proof_status containing all prove
  information available.
-}
proof_stat :: AS_Anno.Named SPTerm -- ^ goal to prove
           -> Maybe GoalStatus -- ^ Nothing stands for prove error
           -> [String] -- ^ Used axioms in the proof
           -> Bool -- ^ Timeout status
           -> Proof_status () -- ^ default proof status
           -> (ATPRetval, Proof_status ())
           -- ^ General return value of a prover run, used in GUI.
           --   Detailed proof status if information is available.
proof_stat nGoal res usedAxs timeOut defaultPrStat
  | isNothing res =
      (ATPError "Internal error.", defaultPrStat)
  | (fromJust res == Proved Nothing) =
      (ATPSuccess, defaultPrStat
       { goalStatus = Proved $ if elem (AS_Anno.senName nGoal) usedAxs
                               then Nothing
                               else Just False
       , usedAxioms = filter (/=(AS_Anno.senName nGoal)) usedAxs })
  | (fromJust res == Disproved) =
      (ATPSuccess, defaultPrStat { goalStatus = Disproved } )
  | isJust res && timeOut =
      (ATPTLimitExceeded,
       defaultPrStat { goalStatus = fromJust res })
  | otherwise = (ATPSuccess, defaultPrStat)
