
{- HetCATS/HasCASL/ParseTerm.hs
   $Id$
   Authors: Christian Maeder
   Year:    2002
   
   parser for HasCASL kind, types, terms and pattern/equations
-}

module ParseTerm where

import Id
import Keywords
import Lexer
import List(nub)
import Token
import HToken
import As
import Parsec

noQuMark :: String -> GenParser Char st Token
noQuMark s = try $ asKey s << notFollowedBy (char '?')

colT, plusT, minusT, qColonT :: GenParser Char st Token

colT = noQuMark colonS
plusT = asKey plusS
minusT = asKey minusS
qColonT = asKey (colonS++quMark)

quColon :: GenParser Char st (Partiality, Token)
quColon = do c <- colT
	     return (Total, c)
	  <|> 
	  do c <- qColonT
	     return (Partial, c) 

-----------------------------------------------------------------------------
-- kind
-----------------------------------------------------------------------------
-- universe is just a special classId ("Type")
parseClass :: GenParser Char st Class
parseClass = fmap (\c -> if showId c "" == "Type" 
		   then Intersection [] [posOfId c]
		   else Intersection [c] []) classId
             <|> 
	     do o <- oParenT
		(cs, ps) <- parseClass `separatedBy` commaT
		c <- cParenT
		return (Intersection (nub $ concatMap iclass cs) 
			(toPos o ps c))

extClass :: GenParser Char st ExtClass
extClass = do c <- parseClass
	      do s <- plusT
	         return (ExtClass c CoVar (tokPos s))
	       <|> 
	       do s <- minusT
	          return (ExtClass c ContraVar (tokPos s))
	       <|> return (ExtClass c InVar nullPos)

prodClass :: GenParser Char st ProdClass
prodClass = do (cs, ps) <- extClass `separatedBy` crossT
	       return (ProdClass cs (map tokPos ps))

kind :: GenParser Char st Kind
kind = kindOrClass [] []

kindOrClass, curriedKind :: [ProdClass] -> [Token] -> GenParser Char st Kind
kindOrClass os ps = do c@(ProdClass cs _) <- prodClass
		       if let isClass (ExtClass _ InVar _) = True
			      isClass _ = False
			  in length cs == 1 && isClass (head cs)
		         then curriedKind (os++[c]) ps 
				<|> return (Kind os ( (\ (ExtClass e _ _) 
						       -> e) (head cs)) 
				     (map tokPos ps))
		         else curriedKind (os++[c]) ps

curriedKind os ps = do a <- asKey funS
		       kindOrClass os (ps++[a])

-----------------------------------------------------------------------------
-- type
-----------------------------------------------------------------------------
-- a parsed type may also be interpreted as a kind (by the mixfix analysis)

typeToken :: GenParser Char st Type
typeToken = fmap TypeToken (pToken (scanWords <|> placeS <|> 
				    reserved (equalS: hascasl_type_ops)
				    scanSigns))

braces :: GenParser Char st a -> ([a] -> [Pos] -> b) 
       -> GenParser Char st b
braces p c = bracketParser p oBraceT cBraceT commaT c

data TokenMode = AnyToken
               | NoToken String   

-- [...] may contain types or ids
aToken :: TokenMode -> GenParser Char st Token
aToken b = pToken (scanQuotedChar <|> scanDotWords 
		   <|> scanDigit <|> scanWords <|> placeS <|> 
		   case b of 
		   AnyToken -> scanSigns 
		   NoToken s -> reserved [s] scanSigns)

idToken :: GenParser Char st Token
idToken = aToken AnyToken

primTypeOrId, typeOrId :: GenParser Char st Type
primTypeOrId = fmap TypeToken idToken
	       <|> braces typeOrId (BracketType Braces)
	       <|> brackets typeOrId (BracketType Squares)
	       <|> bracketParser typeOrId oParenT cParenT commaT
		       (BracketType Parens)
	       
typeOrId = do ts <- many1 primTypeOrId
	      let t = if length ts == 1 then head ts
 		      else MixfixType ts
		 in 
		 kindAnno t
 		 <|> 
		 return(t)

kindAnno :: Type -> GenParser Char st Type
kindAnno t = do c <- colT 
		k <- kind
		return (KindedType t k (tokPos c))

primType, lazyType, mixType, prodType, funType :: GenParser Char st Type
primType = typeToken 
	   <|> bracketParser parseType oParenT cParenT commaT 
		   (BracketType Parens)
	   <|> braces parseType (BracketType Braces)
           <|> brackets typeOrId (BracketType Squares)

lazyType = do q <- quMarkT
	      t <- primType 
              return (LazyType t (tokPos q))
	   <|> primType

mixType = do ts <- many1 lazyType
             let t = if length ts == 1 then head ts else MixfixType ts
	       in kindAnno t
		  <|> return t 

prodType = do (ts, ps) <- mixType `separatedBy` crossT
	      return (if length ts == 1 then head ts 
		      else ProductType ts (map tokPos ps)) 

funType = do (ts, as) <- prodType `separatedBy` arrowT
	     return (makeFun ts as)
	       where makeFun [t] [] = t
	             makeFun [t,r] [a] = FunType t (fst a) r [snd a]
		     makeFun (t:r) (a:b) = makeFun [t, makeFun r b] [a]
		     makeFun _ _ = error "makeFun got illegal argument"

arrowT :: GenParser Char st (Arrow, Pos)
arrowT = do a <- noQuMark funS
	    return (FunArr, tokPos a)
	 <|>
	 do a <- asKey pFun
	    return (PFunArr, tokPos a)
	 <|>
	 do a <- noQuMark contFun
	    return (ContFunArr, tokPos a)
         <|>
	 do a <- asKey pContFun 
	    return (PContFunArr, tokPos a)

parseType :: GenParser Char st Type
parseType = funType  

-----------------------------------------------------------------------------
-- var decls, typevar decls, genVarDecls
-----------------------------------------------------------------------------

varDecls :: GenParser Char st [VarDecl]
varDecls = do (vs, ps) <- var `separatedBy` commaT
	      varDeclType vs ps

varDeclType :: [Var] -> [Token] -> GenParser Char st [VarDecl]
varDeclType vs ps = do c <- colT
		       t <- parseType
		       return (makeVarDecls vs ps t (tokPos c))

makeVarDecls :: [Var] -> [Token] -> Type -> Pos -> [VarDecl]
makeVarDecls vs ps t q = zipWith (\ v p -> VarDecl v t Comma (tokPos p))
		     (init vs) ps ++ [VarDecl (last vs) t Other q]

varDeclDownSet :: [TypeVar] -> [Token] -> GenParser Char st [TypeVarDecl]
varDeclDownSet vs ps = 
		    do l <- lessT
		       t <- parseType
		       return (makeTypeVarDecls vs ps (Downset t) (tokPos l))

typeVarDecls :: GenParser Char st [TypeVarDecl]
typeVarDecls = do (vs, ps) <- typeVar `separatedBy` commaT
		  do   c <- colT
		       t <- parseClass
		       return (makeTypeVarDecls vs ps t (tokPos c))
		    <|> varDeclDownSet vs ps
		    <|> return (makeTypeVarDecls vs ps 
				universe nullPos)

makeTypeVarDecls :: [TypeVar] -> [Token] -> Class -> Pos -> [TypeVarDecl]
makeTypeVarDecls vs ps c q = let cl = Kind [] c [] in 
    zipWith (\ v p -> 
	     TypeVarDecl (simpleIdToId v) cl Comma (tokPos p))
		(init vs) ps 
		++ [TypeVarDecl (simpleIdToId $ last vs) cl Other q]

genVarDecls:: GenParser Char st [GenVarDecl]
genVarDecls = do (vs, ps) <- var `separatedBy` commaT
		 if all isSimpleId vs then 
		       fmap (map GenVarDecl) (varDeclType vs ps)
		       <|> fmap (map GenTypeVarDecl)
			       (varDeclDownSet (map (\ (Id ts _ _) 
						     -> head ts) vs) ps)
		    else 
		    fmap (map GenVarDecl) (varDeclType vs ps)

isSimpleId :: Id -> Bool
isSimpleId (Id ts _ _) = null (tail ts) && head (tokStr (head ts)) 
			 `elem` caslLetters
				 
-----------------------------------------------------------------------------
-- typeArgs
-----------------------------------------------------------------------------

extTypeVar :: GenParser Char st (TypeVar, Variance, Pos) 
extTypeVar = do t <- typeVar
		do   a <- plusT
		     return (t, CoVar, tokPos a)
	 	  <|>
		  do a <- plusT
		     return (t, ContraVar, tokPos a)
		  <|> return (t, InVar, nullPos)

typeArgs :: GenParser Char st [TypeArg]
typeArgs = do (ts, ps) <- extTypeVar `separatedBy` commaT
	      do   c <- colT
                   if let isInVar(_, InVar, _) = True
			  isInVar(_,_,_) = False
		      in all isInVar ts then 
		      do k <- extClass
			 return (makeTypeArgs ts ps (tokPos c) k)
		      else do k <- parseClass
			      return (makeTypeArgs ts ps (tokPos c) 
				      (ExtClass k InVar nullPos))
	        <|> 
	        do l <- lessT
		   t <- parseType
		   return (makeTypeArgs ts ps (tokPos l)
			   (ExtClass (Downset t) InVar nullPos))
		<|> return (makeTypeArgs ts ps nullPos extUniverse)
		where mergeVariance k e (t, InVar, _) p = 
			  TypeArg t e k p 
		      mergeVariance k (ExtClass c _ _) (t, v, ps) p =
			  TypeArg t (ExtClass c v ps) k p
		      mergeVariance k e (t, _, _) p = TypeArg t e k p
		      makeTypeArgs ts ps q e = 
                         zipWith (mergeVariance Comma e) (init ts) 
				     (map tokPos ps)
			     ++ [mergeVariance Other e (last ts) q]


-----------------------------------------------------------------------------
-- type pattern
-----------------------------------------------------------------------------

typePatternToken, primTypePatternOrId, typePatternOrId 
    :: GenParser Char st TypePattern
typePatternToken = fmap TypePatternToken (pToken (scanWords <|> placeS <|> 
				    reserved [lessS, equalS] scanSigns))

primTypePatternOrId = fmap TypePatternToken idToken 
	       <|> braces typePatternOrId (BracketTypePattern Braces)
	       <|> brackets typePatternOrId (BracketTypePattern Squares)
	       <|> bracketParser typePatternArgs oParenT cParenT semiT
		       (BracketTypePattern Parens)

typePatternOrId = do ts <- many1 primTypePatternOrId
		     return( if length ts == 1 then head ts
 			     else MixfixTypePattern ts)

typePatternArgs, primTypePattern, typePattern :: GenParser Char st TypePattern
typePatternArgs = fmap TypePatternArgs typeArgs

primTypePattern = typePatternToken 
	   <|> bracketParser typePatternArgs oParenT cParenT semiT 
		   (BracketTypePattern Parens)
	   <|> braces typePattern (BracketTypePattern Braces)
           <|> brackets typePatternOrId (BracketTypePattern Squares)

typePattern = do ts <- many1 primTypePattern
                 let t = if length ts == 1 then head ts 
			 else MixfixTypePattern ts
	           in return t

-----------------------------------------------------------------------------
-- pattern
-----------------------------------------------------------------------------
-- a parsed pattern may also be interpreted as a type (by the mixfix analysis)
-- thus [ ... ] may be a mixfix-pattern, a compound list, 
-- or an instantiation with types

-- special pattern needed that don't contain "->" at the top-level
-- because "->" should be recognized in case-expressions

-- flag b allows "->" in patterns 

tokenPattern :: TokenMode -> GenParser Char st Pattern
tokenPattern b = fmap PatternToken (aToken b)
					  
primPattern :: TokenMode -> GenParser Char st Pattern
primPattern b = tokenPattern b 
		<|> braces pattern (BracketPattern Braces) 
		<|> brackets pattern (BracketPattern Squares)
		<|> bracketParser patterns oParenT cParenT semiT 
			(BracketPattern Parens)

patterns :: GenParser Char st Pattern
patterns = do (ts, ps) <- pattern `separatedBy` commaT
	      let tp = if length ts == 1 then head ts 
		       else TuplePattern ts (map tokPos ps)
		  in return tp

mixPattern :: TokenMode -> GenParser Char st Pattern
mixPattern b = 
    do l <- many1 $ primPattern b
       let p = if length l == 1 then head l else MixfixPattern l
	   in typedPattern p <|> return p

typedPattern :: Pattern -> GenParser Char st Pattern
typedPattern p = do { c <- colT
		    ; t <- parseType
		    ; return (TypedPattern p t [tokPos c])
		    }

asPattern :: TokenMode -> GenParser Char st Pattern
asPattern b = 
    do v <- mixPattern b
       do   c <- asT 
	    t <- mixPattern b 
	    return (AsPattern v t [tokPos c])
         <|> return v

pattern :: GenParser Char st Pattern
pattern = asPattern AnyToken

-----------------------------------------------------------------------------
-- instOpId
-----------------------------------------------------------------------------
-- places may follow instantiation lists

instOpId :: GenParser Char st InstOpId
instOpId = do i@(Id is cs ps) <- uninstOpId
	      if isPlace (last is) then return (InstOpId i []) 
		   else do l <- many (brackets parseType Types)
			   u <- many placeT
			   return (InstOpId (Id (is++u) cs ps) l)

-----------------------------------------------------------------------------
-- typeScheme
-----------------------------------------------------------------------------

typeScheme :: GenParser Char st TypeScheme
typeScheme = do f <- forallT
		(ts, cs) <- typeVarDecls `separatedBy` semiT
		d <- dotT
		t <- typeScheme
                return $ case t of 
			 SimpleTypeScheme ty ->
			     TypeScheme (concat ts) 
					    ([] :=> ty) 
					    (toPos f cs d)
			 TypeScheme ots q ps ->
			     TypeScheme (concat ts ++ ots) q
					(ps ++ toPos f cs d)
	     <|> fmap SimpleTypeScheme parseType

-----------------------------------------------------------------------------
-- term
-----------------------------------------------------------------------------

tToken :: GenParser Char st Token
tToken = pToken(scanFloat <|> scanString 
		       <|> scanQuotedChar <|> scanDotWords <|> scanWords 
		       <|> scanSigns <|> placeS <?> "id/literal" )

termToken :: GenParser Char st Term
termToken = fmap TermToken (asKey exEqual <|> asKey equalS <|> tToken)

-- flag if within brackets: True allows "in"-Terms
primTerm :: TypeMode -> GenParser Char st Term
primTerm b = termToken
	   <|> braces term (BracketTerm Braces)
	   <|> brackets term  (BracketTerm Squares)
 	   <|> parenTerm
           <|> forallTerm b 
	   <|> exTerm b 
	   <|> lambdaTerm b 
	   <|> caseTerm b
	   <|> letTerm b

parenTerm :: GenParser Char st Term
parenTerm = do o <- oParenT
	       varTerm o
	         <|>
		 qualOpName o
		 <|> 
		 qualPredName o
		 <|>
		 do (ts, ps) <- option ([],[]) (term `separatedBy` commaT)
		    p <- cParenT
		    return (BracketTerm Parens ts (toPos o ps p))
		     		
partialTypeScheme :: GenParser Char st (Token, TypeScheme)
partialTypeScheme = do q <- qColonT
		       t <- parseType 
		       return (q, SimpleTypeScheme 
			       (FunType (BracketType Parens [] [tokPos q]) 
				PFunArr t [tokPos q]))
		    <|> bind (,) colT typeScheme

varTerm :: Token -> GenParser Char st Term
varTerm o = do v <- asKey varS
	       i <- var
	       c <- colT
	       t <- parseType
	       p <- cParenT
	       return (QualVar i t (toPos o [v, c] p))

qualOpName :: Token -> GenParser Char st Term
qualOpName o = do { v <- asKey opS
		  ; i <- instOpId
 	          ; (c, t) <- partialTypeScheme
		  ; p <- cParenT
		  ; return (QualOp i t (toPos o [v, c] p))
		  }

predTypeScheme :: Pos -> TypeScheme -> TypeScheme
predTypeScheme p (SimpleTypeScheme t) = SimpleTypeScheme (predType p t)
predTypeScheme p (TypeScheme vs (qs :=> t) ps) = 
    TypeScheme vs (qs :=> predType p t) ps

predType :: Pos -> Type -> Type
predType p t = FunType t PFunArr (BracketType Parens [] [p]) []

qualPredName :: Token -> GenParser Char st Term
qualPredName o = do { v <- asKey predS
		    ; i <- instOpId
		    ; c <- colT 
		    ; t <- typeScheme
		    ; p <- cParenT
		    ; return (QualOp i (predTypeScheme (tokPos c) t) 
			      (toPos o [v, c] p))
		  }

data TypeMode = NoIn | WithIn

typeQual :: TypeMode -> GenParser Char st (TypeQual, Token) 
typeQual m = 
	      do q <- colT
	         return (OfType, q)
	      <|> 
	      do q <- asT
	         return (AsType, q)
	      <|> 
	      case m of 
		     NoIn -> pzero
		     WithIn -> 
			 do q <- asKey inS
			    return (InType, q)

typedTerm :: Term -> TypeMode -> GenParser Char st Term
typedTerm f b = 
    do (q, p) <- typeQual b
       t <- parseType
       return (TypedTerm f q t (tokPos p))

typedMixTerm :: TypeMode -> GenParser Char st Term
typedMixTerm b = 
    do ts <- many1 $ primTerm b
       let t = if length ts == 1 then head ts else MixfixTerm ts
	   in typedTerm t b <|> return t

-- typedMixTerm may be separated by "=" or other non-type tokens
mixTerm :: TypeMode -> GenParser Char st Term
mixTerm b = 
    do ts <- many1 $ typedMixTerm b
       return $ if length ts == 1 then head ts else MixfixTerm ts

term :: GenParser Char st Term
term = mixTerm WithIn
       

-----------------------------------------------------------------------------
-- quantified term
-----------------------------------------------------------------------------

forallTerm :: TypeMode -> GenParser Char st Term
forallTerm b = 
             do f <- forallT
		(vs, ps) <- genVarDecls `separatedBy` semiT
		d <- dotT
		t <- mixTerm b
		return (QuantifiedTerm Universal (concat vs) t 
			(toPos f ps d))

exQuant :: GenParser Char st (Quantifier, Id.Token)
exQuant =
        do { q <- asKey (existsS++exMark)
	   ; return (Unique, q)
	   }
        <|>
        do { q <- asKey existsS
	   ; return (Existential, q)
	   }

exTerm :: TypeMode -> GenParser Char st Term
exTerm b = 
         do { (q, p) <- exQuant
	    ; (vs, ps) <- varDecls `separatedBy` semiT
	    ; d <- dotT
	    ; f <- mixTerm b
	    ; return (QuantifiedTerm q (map GenVarDecl (concat vs)) f
		      (toPos p ps d))
	    }

lamDot :: GenParser Char st (Partiality, Token)
lamDot = do d <- asKey (dotS++exMark) <|> asKey (cDot++exMark)
	    return (Total,d)
	 <|> 
	 do d <- dotT
	    return (Partial,d)

lambdaTerm :: TypeMode -> GenParser Char st Term
lambdaTerm b = 
             do l <- asKey lamS
		pl <- lamPattern
		(k, d) <- lamDot      
		t <- mixTerm b
		return (LambdaTerm pl k t (toPos l [] d))

lamPattern :: GenParser Char st [Pattern]
lamPattern = do (vs, ps) <- varDecls `separatedBy` semiT
		return [PatternVars (concat vs) (map tokPos ps)]
	     <|> 
	     many (bracketParser patterns oParenT cParenT semiT 
		      (BracketPattern Parens)) 

-----------------------------------------------------------------------------
-- case-term
-----------------------------------------------------------------------------
-- b1 allows "->", b2 allows "in"-Terms

patternTermPair :: TokenMode -> TypeMode -> String -> GenParser Char st ProgEq
patternTermPair b1 b2  sep = 
    do p <- asPattern b1
       s <- asKey sep
       t <- mixTerm b2
       return (ProgEq p t (tokPos s))

caseTerm :: TypeMode -> GenParser Char st Term
caseTerm b = 
           do c <- asKey caseS
	      t <- term
	      o <- asKey ofS
	      (ts, ps) <- patternTermPair (NoToken funS) b funS 
			  `separatedBy` barT
	      return (CaseTerm t ts (map tokPos (c:o:ps)))

-----------------------------------------------------------------------------
-- let-term
-----------------------------------------------------------------------------

letTerm :: TypeMode -> GenParser Char st Term
letTerm b = 
          do l <- asKey letS
	     (es, ps) <- patternTermPair (NoToken equalS) NoIn equalS 
			 `separatedBy` semiT 
	     i <- asKey inS
	     t <- mixTerm b
	     return (LetTerm es t (toPos l ps i))
