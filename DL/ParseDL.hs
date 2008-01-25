{- |
Module      :  $Header$
Description :  Parser for DL logic
Copyright   :  Dominik Luecke, Uni Bremen 2007
License     :  similar to LGPL, see HetCATS/LICENSE.txt or LIZENZ.txt

Maintainer  :  luecke@informatik.uni-bremen.de
Stability   :  provisional
Portability :  portable

Parser for the DL Concrete Syntax
-}

module DL.ParseDL where

import Common.AnnoState
import Common.Id
import Common.Lexer
import DL.DLKeywords

import DL.AS

import Text.ParserCombinators.Parsec

-- | parse a simple word not in 'casl_dl_keywords'
csvarId :: [String] -> GenParser Char st Token
csvarId ks = pToken (reserved (ks++casl_dl_keywords) scanAnyWords)

stringLit :: GenParser Char st [Char]
stringLit = enclosedBy (flat $ many $ single (noneOf "\\\"")
                        <|> char '\\' <:> single anyChar) $ char '\"'

-- | parser for Concepts
pDLConcept :: GenParser Char (AnnoState st) DLConcept
pDLConcept = do
  chainr1 orConcept (asKey dlxor >> return DLXor)
    where
      orConcept :: GenParser Char (AnnoState st) DLConcept
      orConcept = do 
               chainr1 andConcept (asKey dlor >> return DLOr)
                       
      andConcept :: GenParser Char (AnnoState st) DLConcept 
      andConcept = do
               chainr1 notConcept (asKey dland >> return DLAnd)

      notConcept :: GenParser Char (AnnoState st) DLConcept
      notConcept = do
               asKey dlnot
               i <- infixCps
               return $ DLNot i
             <|> infixCps

      infixCps :: GenParser Char (AnnoState st) DLConcept
      infixCps = do
               i <- relationP
               case i of
                 DLThat _ _ -> restCps i
                 _ -> option i (restCps i)

      relationP :: GenParser Char (AnnoState st) DLConcept
      relationP = do
               p <- primC 
               option p $ do 
                    asKey dlthat
                    p2 <- primC
                    return (DLThat p p2)

      primC :: GenParser Char (AnnoState st) DLConcept
      primC = do
               fmap (\x -> DLClassId $ mkId (x:[])) (csvarId casl_dl_keywords)
             <|> 
             do
               between oParenT cParenT pDLConcept
             <|> 
             do
               oBraceT
               is <- sepBy1 (csvarId casl_dl_keywords) commaT
               cBraceT
               return $ DLOneOf $ map (mkId . (: [])) is

      restCps :: DLConcept -> GenParser Char (AnnoState st) DLConcept
      restCps i = do
               asKey dlsome
               p <- relationP
               return $ DLSome i p                  
             <|>  do
               asKey dlonly
               p <- relationP
               return $ DLOnly i p 
             <|>  do
               asKey dlhas
               p <- relationP
               return $ DLHas i p 
             <|> do
               asKey dlmin
               p <- fmap read $ many1 digit
               return $ DLMin i p 
             <|> do
               asKey dlmax
               p <- fmap read $ many1 digit
               return $ DLMin i p 
             <|> do
               asKey dlexact
               p <- fmap read $ many1 digit
               return $ DLMin i p
             <|> do
               asKey dlvalue
               p <- csvarId casl_dl_keywords
               return $ DLValue i (simpleIdToId p)
             <|> do
               asKey dlonlysome
               oBracketT
               is <- sepBy1 pDLConcept commaT
               cBracketT
               return $ DLOnlysome i is

-- | Auxiliary parser for classes
cscpParser :: GenParser Char (AnnoState st) DLClassProperty
cscpParser = 
    do 
      try $ string dlSub
      spaces
      s <- sepBy pDLConcept commaT
      return $ DLSubClassof s
    <|>
    do
      try $ string dlEquivTo
      spaces
      s <- sepBy pDLConcept commaT
      return $ DLEquivalentTo s
    <|>
    do
      try $ string dlDisjoint
      spaces
      s <- sepBy pDLConcept commaT
      return $ DLDisjointWith s

-- ^ The CASL_DL Syntax Parser for basic items
csbiParse :: GenParser Char (AnnoState st) DLBasicItem
csbiParse = 
    do 
      try $ spaces >> string dlclass
      spaces
      cId   <- csvarId casl_dl_keywords
      props <- many cscpParser
      para <- parsePara
      return $ DLClass (simpleIdToId cId) props para
    <|> 
    do
      try $ spaces >> string dlValPart
      spaces
      cId   <- csvarId casl_dl_keywords
      oBracketT
      is <- sepBy1 (csvarId casl_dl_keywords) commaT
      cBracketT
      para <- parsePara
      return $ DLValPart (simpleIdToId cId) (map (mkId . (: [])) is) para
    <|> 
    do
      try $ spaces >> string dlObjProp
      spaces
      cId   <- csvarId casl_dl_keywords
      dom   <- csDomain
      ran   <- csRange
      probRel <- many csPropsRel
      csChars <- parseDLChars
      para <- parsePara
      return $ DLObjectProperty (simpleIdToId cId) dom ran probRel csChars para
    <|> 
    do
      try $ spaces >> string dlDataProp
      spaces
      cId   <- csvarId casl_dl_keywords
      dom   <- csDomain
      ran   <- csRange
      probRel <- many csPropsRelD
      csCharsD <- parseDLCharsD
      para <- parsePara
      return $ DLDataProperty (simpleIdToId cId) dom ran probRel csCharsD para
    <|>
    do
      try $ spaces >> string dlIndi
      spaces
      iId <- csvarId casl_dl_keywords
      ty  <- parseType
      facts <- parseFacts
      indrel <- csIndRels
      para <- parsePara
      return $ DLIndividual (simpleIdToId iId) ty facts indrel para

-- | Parser for characteristics for data props
-- | Parser for lists of characteristics
parseDLCharsD :: GenParser Char st (Maybe DLChars)
parseDLCharsD = 
    do 
      try $ string dlChar
      spaces
      chars <- csCharD
      return (Just $ chars)
    <|>
    do
      return Nothing
    where
      csCharD :: GenParser Char st DLChars
      csCharD =
          do
            try $ string dlFunc
            spaces 
            return DLFunctional

-- | Parser for lists of characteristics
parseDLChars :: GenParser Char st [DLChars]
parseDLChars = 
    do 
      try $ string dlChar
      spaces
      chars <- sepBy csChar commaT
      return chars
    <|>
    do
      return []
    where
      csChar :: GenParser Char st DLChars
      csChar =
          do
            try $ string dlFunc
            spaces 
            return DLFunctional
          <|>
          do
            try $ string dlInvFunc
            spaces
            return DLInvFuntional
          <|>
          do
            try $ string dlSym
            spaces
            return DLSymmetric
          <|>
          do
            try $ string dlTrans
            spaces
            return DLTransitive

-- | Parser for domain
csDomain :: GenParser Char st (Maybe Id)
csDomain = 
    do 
      try $ string dlDomain
      spaces
      dID <- csvarId casl_dl_keywords
      return $ Just (simpleIdToId dID)
    <|>
    do
      return Nothing

-- | Parser for range
csRange :: GenParser Char st (Maybe Id)
csRange = 
    do 
      try $ string dlRange
      spaces
      dID <- csvarId casl_dl_keywords
      return $ Just (simpleIdToId dID)
    <|>
    do
      return Nothing
      
-- | Parser for property relations
csPropsRel :: GenParser Char st DLPropsRel
csPropsRel =
    do
      try $ string dlSubProp
      spaces
      is <- sepBy1 (csvarId casl_dl_keywords) commaT
      return $ DLSubProperty $ map (mkId . (: [])) is
    <|>
    do
      try $ string dlInv
      spaces
      is <- sepBy1 (csvarId casl_dl_keywords) commaT
      return $ DLInverses $ map (mkId . (: [])) is
    <|>
     do
      try $ string dlInvOf
      spaces
      is <- sepBy1 (csvarId casl_dl_keywords) commaT
      return $ DLInverses $ map (mkId . (: [])) is   
    <|>
    do
      try $ string dlEquiv
      spaces
      is <- sepBy1 (csvarId casl_dl_keywords) commaT
      return $ DLEquivalent $ map (mkId . (: [])) is
    <|>
    do
      try $ string dlDis
      spaces
      is <- sepBy1 (csvarId casl_dl_keywords) commaT
      return $ DLDisjoint $ map (mkId . (: [])) is

-- | Parser for property relations
csPropsRelD :: GenParser Char st DLPropsRel
csPropsRelD =
    do
      try $ string dlSubProp
      spaces
      is <- sepBy1 (csvarId casl_dl_keywords) commaT
      return $ DLSubProperty $ map (mkId . (: [])) is
    <|>
    do
      try $ string dlEquiv
      spaces
      is <- sepBy1 (csvarId casl_dl_keywords) commaT
      return $ DLEquivalent $ map (mkId . (: [])) is
    <|>
    do
      try $ string dlDis
      spaces
      is <- sepBy1 (csvarId casl_dl_keywords) commaT
      return $ DLDisjoint $ map (mkId . (: [])) is

-- | Parser for types
parseType :: GenParser Char st (Maybe DLType)
parseType =
    do
      try $ string dlTypes
      spaces
      ty <- sepBy1 (csvarId casl_dl_keywords) commaT 
      return $ Just (DLType $ map (mkId . (: [])) ty)
    <|> return Nothing

-- | Parser for facts
parseFacts :: GenParser Char st [DLFacts]
parseFacts = 
    do 
      try $ string dlFacts
      spaces
      facts <-  sepBy1 parseFact commaT
      return facts
    <|>
    do
      return []
    where
      parseFact :: GenParser Char st DLFacts
      parseFact = 
          do 
            is <- csvarId casl_dl_keywords
            spaces
            os <- csvarId casl_dl_keywords
            return $ DLPosFact ((\(x,y) -> (simpleIdToId x, simpleIdToId y)) (is,os))
          <|>
          do
            try $ string dlnot
            spaces
            is <- csvarId casl_dl_keywords
            spaces
            os <- csvarId casl_dl_keywords
            return $ DLNegFact ((\(x,y) -> (simpleIdToId x, simpleIdToId y)) (is,os))

-- | Parser for relations between individuals
csIndRels :: GenParser Char st [DLIndRel]
csIndRels =
    do
      is <- many csIndRel
      return is
    where
      csIndRel :: GenParser Char st DLIndRel
      csIndRel = 
          do
            try $ string dlDiff
            spaces
            is <- sepBy1 (csvarId casl_dl_keywords) commaT
            return $ DLDifferentFrom $ map (mkId . (: [])) is
          <|>
          do
            try $ string dlSame
            spaces
            is <- sepBy1 (csvarId casl_dl_keywords) commaT
            return $ DLDifferentFrom $ map (mkId . (: [])) is    

-- ^ the toplevel parser for CASL_DL Syntax
csbsParse :: GenParser Char (AnnoState st) DLBasic
csbsParse = 
    do 
      biS <- many csbiParse
      return $ DLBasic biS

testParse :: [Char] -> Either ParseError DLBasic
testParse st = runParser csbsParse (emptyAnnos ()) "" st

longTest :: IO (Either ParseError DLBasic)
longTest = do x <- (readFile "DL/test/Pizza.het"); return $ testParse x

-- ^ Parser for Paraphrases
parsePara :: GenParser Char st (Maybe DLPara)
parsePara = 
	do
		try $ string dlPara
		spaces
		paras <- many1 $ parseMultiPara
		return $ Just $ DLPara paras
	<|> do
		return Nothing	
	where
	parseMultiPara :: GenParser Char st (ISOLangCode, [Char])
	parseMultiPara = 
		do
			pp <- stringLit
			spaces 
			lg <- parseLang
			return (lg, pp)

	parseLang ::  GenParser Char st ISOLangCode
	parseLang = 
		do
			try $ oBracketT
			string dlLang
			spaces
			lg1 <- letter
			lg2 <- letter
			spaces
			cBracketT	
			return ([lg1] ++ [lg2])
		<|> return "en"

instance AParsable DLBasicItem where
    aparser = csbiParse

instance AParsable DLBasic where
    aparser = csbsParse

instance AParsable DLClassProperty where
    aparser = cscpParser

instance AParsable DLConcept where
    aparser = pDLConcept
