import System.Environment

import OWL2.XML
import Text.XML.Light

processFile :: String -> IO ()
processFile file = do
  s <- readFile file
  case parseXMLDoc s of 
    Nothing -> fail "error"
    Just elems -> putStrLn $ show $ getClassAxiom elems 

main :: IO ()
main = do
  args <- getArgs
  mapM_ processFile args