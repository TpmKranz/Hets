{- |
Module      :  $Header$
Description :  Constants and related fucntions for CspCASLProver
Copyright   :  (c) Liam O'Reilly and Markus Roggenbach,
                   Swansea University 2008
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  csliam@swansea.ac.uk
Stability   :  provisional
Portability :  non-portable (imports Logic.Logic)

Constants and related fucntions for CspCASLProver.

-}

module CspCASLProver.Consts
    ( alphabetS
    , alphabetType
    , binEq_PreAlphabet
    , classOp
    , classS
    , convertProcessName2String
    , convertSort2String
    , cspFThyS
    , eq_PreAlphabetS
    , eq_PreAlphabetV
    , eqvTypeClassS
    , equivTypeClassS
    , preAlphabetQuotType
    , preAlphabetS
    , preAlphabetSimS
    , preAlphabetType
    , mkChooseFunName
    , mkCompareWithFunName
    , mkPreAlphabetConstructor
    , mkProcNameConstructor
    , mkSortBarString
    , mkThyNameAlphabet
    , mkThyNameDataEnc
    , mkThyNameIntThms
    , mkThyNamePreAlphabet
    , procMapS
    , procMapType
    , procNameType
    , quotEqualityS
    , quotientThyS
    , reflexivityTheoremS
    , symmetryTheoremS
    , transitivityS
    ) where

import CASL.AS_Basic_CASL (SORT)
import CspCASL.AS_CspCASL_Process (PROCESS_NAME)
import Isabelle.IsaConsts (binVNameAppl, conDouble, mkFunType, termAppl)
import Isabelle.IsaSign (BaseSig(..), Term, Typ(..), VName(..))
import Isabelle.Translate(showIsaTypeT)

-- | Name for the CspCASLProver's Alphabet
alphabetS :: String
alphabetS = "Alphabet"

-- | Type for the CspCASLProver's Alphabet
alphabetType :: Typ
alphabetType = Type {typeId = alphabetS,
                     typeSort = [],
                     typeArgs =[]}

-- | String for the name extension of CspCASLProver's bar types
barExtS :: String
barExtS = "_Bar"

-- | Isabelle fucntion to compare eqaulity of two elements of the
--   PreAlphabet.
binEq_PreAlphabet :: Term -> Term -> Term
binEq_PreAlphabet = binVNameAppl eq_PreAlphabetV

-- | Type for (ProcName,Alpahbet) proc
cCProverProcType :: Typ
cCProverProcType = Type {typeId = procS,
                         typeSort = [],
                         typeArgs =[procNameType, alphabetType]}

-- | Isabelle operation for the class operation
classOp :: Term -> Term
classOp = termAppl (conDouble classS)

-- | String for the class operation
classS :: String
classS = "class"

-- | Convert a SORT to a string
convertSort2String :: SORT -> String
convertSort2String s = showIsaTypeT s Main_thy

-- | Convert a process name to a string
convertProcessName2String :: PROCESS_NAME -> String
convertProcessName2String = show

-- |  Theory file name for CSP_F of CSP-Prover
cspFThyS :: String
cspFThyS  = "CSP_F"

-- | String of the name of the function to compare eqaulity of two
--   elements of the PreAlphabet.
eq_PreAlphabetS :: String
eq_PreAlphabetS = "eq_PreAlphabet"

-- | VName of the name of the function to compare eqaulity of two
--   elements of the PreAlphabet.
eq_PreAlphabetV :: VName
eq_PreAlphabetV   = VName eq_PreAlphabetS $ Nothing

-- | String for the name of the axiomatic type class of equivalence
--   relations part 1
eqvTypeClassS :: String
eqvTypeClassS  = "eqv"

-- | String for the name of the axiomatic type class of equivalence
--   relations part 2
equivTypeClassS :: String
equivTypeClassS  = "equiv"

-- | Function that takes a sort and outputs a the function name for the
--   corresponing choose function
mkChooseFunName :: SORT -> String
mkChooseFunName sort = ("choose_" ++ (mkPreAlphabetConstructor sort))

-- | Function that takes a sort and outputs the function name for the
--   corresponing compare_with function
mkCompareWithFunName :: SORT -> String
mkCompareWithFunName sort = ("compare_with_" ++ (mkPreAlphabetConstructor sort))

-- | Function that returns the constructor of PreAlphabet for a given
--   sort
mkPreAlphabetConstructor :: SORT -> String
mkPreAlphabetConstructor sort = "C_" ++ (convertSort2String sort)

-- | Given a process name this fucntion returns a unique constructor for that
--   process name. This is a helper functin when buildign the process name data
--   type.
mkProcNameConstructor :: PROCESS_NAME -> String
mkProcNameConstructor pn = show pn

-- | Converts a SORT in to the corresponding bar sort represented as a
-- string
mkSortBarString :: SORT -> String
mkSortBarString s = convertSort2String s ++ barExtS

-- | Created a name for the theory file which stores the alphabet
--   construction for CspCASLProver.
mkThyNameAlphabet :: String -> String
mkThyNameAlphabet thName = thName ++ "_alphabet"

-- | Created a name for the theory file which stores the data encoding
--   for CspCASLProver.
mkThyNameDataEnc :: String -> String
mkThyNameDataEnc thName = thName ++ "_dataenc"

-- | Created a name for the theory file which stores the Alphabet
--   construction and instances code for CspCASLProver.
mkThyNamePreAlphabet :: String -> String
mkThyNamePreAlphabet thName = thName ++ "_prealphabet"

-- | Created a name for the theory file which stores the Integration
--   Theorems for CspCASLProver.
mkThyNameIntThms :: String -> String
mkThyNameIntThms thName = thName ++ "_integrationThms"

-- | Type for CspCASLProver's preAlphabet quot
preAlphabetQuotType :: Typ
preAlphabetQuotType = Type {typeId = quotS,
                            typeSort = [],
                            typeArgs =[preAlphabetType]}

-- | Name for CspCASLProver's PreAlphabet
preAlphabetS :: String
preAlphabetS = "PreAlphabet"

preAlphabetSimS :: String
preAlphabetSimS = "preAlphabet_sim"

-- | Type for CspCASLProver's PreAlphabet
preAlphabetType :: Typ
preAlphabetType = Type {typeId = preAlphabetS,
                        typeSort = [],
                        typeArgs =[]}

-- | Name for CspCASLProver's function for mapping process names to
--   actual processes
procMapS :: String
procMapS = "ProcMap"

-- | Type for CspCASLProver's function for mapping process names to
--   actual processes
procMapType :: Typ
procMapType = mkFunType procNameType cCProverProcType

-- | Name for CspCASLProver's datatype of process names
procNameS :: String
procNameS = "ProcName"

-- | Type for CspCASLProver's datatype of process names
procNameType :: Typ
procNameType = Type {typeId = procNameS,
                     typeSort = [],
                     typeArgs =[]}

-- | name for CspProver's ('pn, 'a) proc type
procS :: String
procS = "proc"

-- | Name for IsabelleHOL quot type
quotS :: String
quotS = "quot"

quotEqualityS :: String
quotEqualityS = "quot_equality"

quotientThyS :: String
quotientThyS = "Quotient"

reflexivityTheoremS :: String
reflexivityTheoremS = "eq_refl"

symmetryTheoremS :: String
symmetryTheoremS = "eq_symm"

transitivityS :: String
transitivityS = "eq_trans"
