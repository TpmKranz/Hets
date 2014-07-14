module UML where
import qualified Data.Map as Map

data Model = ClassModel [Package]
                | StateMachine (Map.Map Id State) [Transition] (Map.Map Id PseudoState)
                | Err String deriving Show

data Package = Package {
        packageName :: String,
        classes :: (Map.Map Id Class),
        associations :: (Map.Map Id Association),
        interfaces :: (Map.Map Id Interface),
        packageMerges :: [Id],
        signals :: (Map.Map Id Signal),
        assoClasses :: (Map.Map Id AssociationClass)} deriving Show

data AssociationClass = AssociationClass {
        acClass :: Class,
        acAsso :: Association} deriving Show
data Class = Class {
        super :: [Id],
        className :: String,
        attr :: [Attribute],
        proc :: [Procedure]
} deriving Show

data Attribute = Attribute {
        attrName :: String,
        attrType :: Type,
        attrUpperValue :: String,
        attrLowerValue :: String,
        attrVisibility :: String
} deriving Show

data Procedure = Procedure {
        procName :: String,
        procPara :: [(String, Type)],
        procReturnType :: Maybe Type,
        procPackImports :: [Id],
        procElemImports :: [Id],
        procVisibility :: String
} deriving Show

data Association = Association {
        ends :: [End]
} deriving Show

data End = End {
endTarget :: Id,
label :: Label
} deriving Show

data Interface = Interface {
interfaceName :: String
} deriving Show

type Id = String
type Type = String

data Label = Label {upperValue :: String,
lowerValue :: String} deriving Show

data Signal = Signal {
        sigSuper :: [Id],
        signalName :: String,
        sigAttr :: [Attribute],
        sigProc :: [Procedure]
} deriving Show
-- begin:StateMachines

data Region = Region {
        states :: [State],
        transitions :: [Transition],
        pseudoStates :: [PseudoState]} deriving Show

data PseudoState = PseudoState {
pseudoStateName :: String,
pseudoStateType :: String
} deriving Show

data State = State {
        region :: Maybe Region,
        stateName :: String
} deriving Show

data Transition = Transition {
        source :: String,
        target :: String,
        trigger :: Trigger,
        guard :: Maybe Guard,
        event :: Maybe Event} deriving Show

type Trigger = String
type Guard = String
type Event = String
