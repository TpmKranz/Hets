
{- HetCATS/CASL/ItemList.hs
   $Id$
   Authors: Christian Maeder
   Year:    2002
   
   generically parse "<keyword>/<keywords> ITEM ; ... ; ITEM"
-}

module ItemList where

import AnnoState
import Id
import Keywords
import Lexer
import AS_Annotation
import Maybe
import Parsec
import Token
import List(delete)

-- ----------------------------------------------
-- annotations
-- ----------------------------------------------

annos, lineAnnos :: AParser [Annotation]
annos = addAnnos >> getAnnos
lineAnnos = addAnnos >> getLineAnnos

-- optional semicolon followed by annotations on the same line
optSemi :: AParser (Maybe Token, [Annotation])
optSemi = do addAnnos
             l <- getLineAnnos
	     a <- getAnnos 
	     do s <- semiT
		addAnnos
		l2 <- getLineAnnos
		return (Just s, l ++ a ++ l2)
	      <|> do setState $ AnnoState [] a
		     return (Nothing, l)

-- succeeds if an item is not continued after a semicolon
tryItemEnd :: [String] -> AParser ()
tryItemEnd l = 
    try (do c <- lookAhead 
			      (single (oneOf "\"([{")
			       <|> placeS
			       <|> scanAnySigns
			       <|> many scanLPD)
	    if null c || c `elem` l then return () else unexpected c)


-- remove quantifier exists from casl_reserved_word 
-- because it may start a formula in "axiom/axioms ... \;"
startKeyword :: [String]
startKeyword = dotS:cDot:
		   (delete existsS casl_reserved_words)

appendAnno :: Annoted a -> [Annotation] -> Annoted a
appendAnno (Annoted x p l r) y = Annoted x p l (r++y)

addLeftAnno :: [Annotation] -> a -> Annoted a
addLeftAnno l i = Annoted i [] l []

annoParser :: AParser a 
	   -> AParser (Annoted a)
annoParser parser = bind addLeftAnno annos parser


annosParser :: AParser a 
	    -> AParser [Annoted a]
annosParser parser = 
    do is <- many1 $ try $ annoParser parser
       a <- annos 
       return (init is ++ [appendAnno (last is) a])

itemList :: String -> AParser b
               -> ([Annoted b] -> [Pos] -> a) -> AParser a
itemList = auxItemList startKeyword

auxItemList :: [String] -> String -> AParser b
            -> ([Annoted b] -> [Pos] -> a) -> AParser a

auxItemList startKeywords keyword parser constr =
    do p <- pluralKeyword keyword
       (vs, ts, ans) <- itemAux startKeywords (annoParser parser)
       let r = zipWith appendAnno vs ans in 
	   return (constr r (map tokPos (p:ts)))

itemAux :: [String] -> AParser a 
	-> AParser ([a], [Token], [[Annotation]])
itemAux startKeywords itemParser = 
    do a <- itemParser
       (m, an) <- optSemi
       case m of Nothing -> return ([a], [], [an])
                 Just t -> do tryItemEnd startKeywords
			      return ([a], [t], [an])
	                   <|> 
	                   do (as, ts, ans) <- itemAux startKeywords itemParser
			      return (a:as, t:ts, an:ans)

