-- |
-- Some helper functions

module Text.XML.HXT.RelaxNG.Utils
where

import Text.XML.HXT.DOM.TypeDefs
  ( QName(..) )
import Text.XML.HXT.DOM.Util
  ( charToHexString )
import Text.ParserCombinators.Parsec
import Text.XML.HXT.Parser.XmlParser
    ( skipS0 )

import Network.URI
  ( isURI
  , isRelativeReference
  , parseURI
  , URI(..)
  )
import Maybe
import Char 


-- ------------------------------------------------------------

-- | Removes leading \/ trailing whitespaces and leading zeros
normalizeNumber :: String -> String
normalizeNumber = reverse . dropWhile (== ' ') . reverse . 
                  dropWhile (\x -> x == '0' || x == ' ')


-- | Reduce whitespace sequences to a single whitespace
normalizeWhitespace :: String -> String
normalizeWhitespace = unwords . words


-- | Escape all disallowed characters in URI 
-- references (see <http://www.w3.org/TR/xlink/#link-locators>)
escapeURI :: String -> String
escapeURI ref = concatMap replace ref
  where
  replace :: Char -> String
  replace c = if fromEnum c < 31 || 
                 (elem c ['\DEL', ' ', '<', '>', '"', '{', '}', '|', '\\', '^', '`' ]) 
              then '%':charToHexString c
              else [c]


-- | Tests whether a URI matches the Relax NG anyURI symbol
isRelaxAnyURI :: String -> Bool
isRelaxAnyURI s 
  = s == "" ||
    ( isURI s && not (isRelativeReference s) &&
      ( let (URI _ _ path _ frag) = fromMaybe (URI "" Nothing "" "" "") $ parseURI s
        in (frag == "" && path /= "")
      )
    )


-- | Tests whether two URIs are equal after 'normalizeURI' is performed
compareURI :: String -> String -> Bool
compareURI uri1 uri2 = normalizeURI uri1 == normalizeURI uri2


-- |  Converts all letters to the corresponding lower-case letter 
-- and removes a trailing \"\/\" 
normalizeURI :: String -> String
normalizeURI ""  = ""
normalizeURI uri = map toLower (if last uri == '/' then init uri else uri)
                  
-- | Tests whether a string matches a number [-](0-9)*
parseNumber :: String -> Bool
parseNumber s
  = case (parse parseNumber' "" s) of
      Left _  -> False
      Right _ -> True
  where
  parseNumber' :: Parser String
  parseNumber'
    = do
      skipS0
      m <- option "" (string "-")
      n <- many1 digit
      skipS0
      eof
      return $ m ++ n
      

{- | 

Formats a list of strings into a single string. The first parameter is inserted
between two elements.

example:

> formatStringList ", " ["foo", "bar", "baz"] -> "foo, bar, baz"

-}
formatStringList :: String -> [String] -> String
formatStringList _ [] = ""
formatStringList spacer l
  = reverse $ drop (length spacer) $ reverse $ 
    foldr (\e -> ((if e /= "" then e ++ spacer else "") ++)) "" l


-- | Formats a qualified name, e.g. \"{namespace}localName\"
qn2String :: QName -> String
qn2String (QN _ lp ns) = "{" ++ ns ++ "}" ++ lp
