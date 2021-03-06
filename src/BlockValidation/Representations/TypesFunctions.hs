{-# LANGUAGE DatatypeContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE AllowAmbiguousTypes #-}

module BlockValidation.Representations.TypesFunctions where

import           Engine.Engine

import           Algebra.Graph.Relation
import qualified Data.Map.Strict      as M
import qualified Data.Set             as S

----------
-- 0 Types
----------
-- HashBlock choice
data (Eq a, Ord a, Show a) => Send a = Send a | DoNotSend
   deriving (Eq,Ord,Show)

-- A view on the previous information
data View a = HashBlock a | Empty
   deriving (Eq,Ord,Show)

type Started = Bool

type Hash = Word
type Player = String
type Vote = Int
type Id    = Int
type Timer = Int
type Weight = Int
type ValidatorMap = M.Map Player Id
-- The chain is represented by the edges (Blocks) and vertices (Which validator voted for that Block to be the head)
type Chain = Relation (Id,Vote)
type WeightedChain = Relation (Id,Weight)
type Fee = Double
type Reward = Double

------------------------
-- 1 Auxiliary functions
------------------------

-- Given a previous chain, id, and a new hash, extend the chain accordingly
-- initially, that vertex has empty votes
-- it is assigned a unique id
-- FIXME What if non existing id?
addToChain :: Chain -> Id -> Chain
addToChain chain id  =
  let newId = vertexCount chain + 1
      -- ^ assign new id using the vertexCount of the existing chain
      newNode = vertex (newId,0)
      -- ^ create new vertex with 0 votes
      vertexRoot = induce (\(x,_) -> x == id) chain
      -- ^ find vertex with the _id_
      newConnection = connect vertexRoot newNode
      -- ^ connect the vertex with the relevant id to new node with label new hash
      in overlay chain newConnection
      -- ^ update the connection of the new chain

-- Given a previous chain and the decision to append or to wait,
-- produce a new chain
addToChainWait :: Chain -> Send Id -> Chain
addToChainWait chain DoNotSend  = chain
-- ^ Keep the old chain
addToChainWait chain (Send id)  = addToChain chain id
-- ^ Append block to old chain (create new chain)


-- Given a previous chain and the decision to append or to wait, a timer and a timer threshold
-- produce a new chain
addToChainWaitTimer :: Timer -> Timer -> Chain ->  Send Id -> Chain
addToChainWaitTimer threshold timer chain decision =
  if timer == threshold
     then addToChainWait chain decision
          -- ^ only at the time of the threshold a new block is added
     else chain
          -- ^ otherwise the same block is kept

-- Produces alternatives for proposer
alternativesProposer :: Chain -> [Send Id]
alternativesProposer chain =
  let noVertices = vertexCount chain
      in DoNotSend : fmap Send [1..noVertices]

-- Find vertex in a chain given unique id
-- FIXME What if non-existing id?
findVertexById :: Chain -> Id -> (Id,Vote)
findVertexById chain id =
  let  verticeLs = vertexList chain
       -- ^ list of vertices
       in (head $ filter (\(id',_) -> id' == id) verticeLs)

-- For validator choose the string which he believes is the head and update the chain accordingly
-- FIXME What if non-existing id?
validatorChoiceIndex :: Chain -> Id -> Chain
validatorChoiceIndex chain id =
  let (id',i) = findVertexById chain id
      in replaceVertex (id',i) (id',i+1) chain

-- Given an initial chain and a list of votes on _Id_s, update the chain
-- FIXME What if non-existing id?
updateVotes :: Chain -> [Id] -> Chain
updateVotes chain [] = chain
updateVotes chain (i:is) = updateVotes (validatorChoiceIndex chain i) is

-- Cycling ticker
transformTicker :: Timer -> Timer
transformTicker 12 = 0
transformTicker x  = x + 1


-- find the head of the chain
determineHead :: Chain -> S.Set Id
determineHead chain =
  let allBranches = findBranches chain
      weightedBranches = S.map (findPath chain) allBranches
      (weightMax,_) = S.findMax $ S.map (\(x,y) -> (y,x)) weightedBranches
      allMax           = S.filter (\(id,weight) -> weight == weightMax) $ weightedBranches
      -- ^ This addresses the case where several end branches hold the same weighted votes
      in S.map fst allMax
  where
    -- find all the branches of a chain
    findBranches :: Chain  -> S.Set (Id,Vote)
    findBranches chain' =
      let  vertexSetChain   = vertexSet chain'
           transChain = transitiveClosure chain'
           setPreSet = S.unions $ S.map (flip preSet transChain) vertexSetChain
           in S.difference vertexSetChain setPreSet
    -- find all the paths from each branch to the root of the chain
    findPath :: Chain -> (Id, Vote) -> (Id, Weight)
    findPath chain' (i,v) =
      let elementsOnPath = preSet (i,v) transitiveChain
          transitiveChain = transitiveClosure chain'
          weight = S.foldr (\(_,j) -> (+) j) 0 elementsOnPath
          in (i,weight + v)
          -- ^ NOTE the value of the last node itself is added as well


-- Is the node the validator voted for on the path to the latest head?
-- FIXME player name, id not given
-- NOTE: This allows validators to cast their votes on previous parts of
-- the chain which are already "deep in the stack"
-- This could be restricted to a certain level of depth
attestedCorrect :: Player -> M.Map Player Id -> Chain -> S.Set Id -> Bool
attestedCorrect name validatorMap chain headOfChainS =
  let headOfChainLs = S.elems headOfChainS
      in and $ fmap (attestedCorrectSingleNode name validatorMap chain) headOfChainLs
  where
    attestedCorrectSingleNode :: Player -> M.Map Player Id -> Chain -> Id -> Bool
    attestedCorrectSingleNode name validatorMap chain headOfChain =
      let idChosen = validatorMap M.! name
          -- ^ id voted for by player
          chosenNode = findVertexById chain idChosen
          -- ^ vertex chosen
          headNode = findVertexById chain headOfChain
          -- ^ vertex which is head of the chain
          chainClosure = closure chain
          -- ^ transitive closure of chain; needed to get all connections
          setOnPath = postSet chosenNode chainClosure
          -- ^ elements that are successors of id'
          in S.member headNode setOnPath
          -- ^ is the head in that successor set?

-- Is there a difference between the head from period t-2 and the head of period t-1?
-- Is used to determine whether the proposer in t-1 actually did something
wasBlockSent :: Chain -> Id -> (Bool,Id)
wasBlockSent chainT1 idT2 =
  let headT1 = maximum $ fst <$> vertexList chainT1
      wasSent = idT2 + 1 == headT1
      in (wasSent,headT1)

-- Did the proposer from (t-1) send the block? Gets rewarded if that block is on the path to the current head(s).
proposedCorrect :: Bool -> Chain -> Bool
proposedCorrect False _     = False
proposedCorrect True chain  =
  let currentHeadIdLs = S.elems $ determineHead chain
      in and $ fmap (proposedCorrectSingleNode chain) currentHeadIdLs 
  where
    proposedCorrectSingleNode :: Chain -> Id -> Bool
    proposedCorrectSingleNode chain currentHeadId =
    -- ^ correctely proposed for a given chain and a given head
      let currentHead   = findVertexById chain currentHeadId
          oldDecisionProposer = vertexCount chain - 1
          -- ^ find the previous decision of the last proposer
          chainClosure  = closure chain
          -- ^ transitive closure of chain
          onPathElems   = preSet currentHead chainClosure
          -- ^ nodes which are on the path to the current head
          pastHead      = findVertexById chain oldDecisionProposer
          -- ^ what is the past node?
          in S.member pastHead onPathElems
             -- ^ is the past head on the path to the current node


-- Given an exogenous threshold, the message will be delayed if before the threshold
-- NOTE: The threshold could be determined internally by a stochastic process
-- But for isolating the reasoning about it, probably better to feed it as
-- and explicit parameter
delayMessage :: Timer -> (Timer, Chain, Chain) -> Chain
delayMessage delayTreshold (actualTimer, oldChain, newChain)
  | actualTimer < delayTreshold = oldChain
  | otherwise                  = newChain

-- transform list to Map; done here due to restrictions of DSL
newValidatorMap :: [(Player,Id)] -> ValidatorMap -> ValidatorMap
newValidatorMap new old = M.union (M.fromList new) old

------------
-- 2 Payoffs
------------

  -- The validator  and the proposer are rewarded if their decision has been evaluated by _attestedCorrect_ resp. _proposedCorrect_ as correct
validatorPayoff successFee verified = if verified then successFee else 0
proposerPayoff reward verified  = if verified then reward else 0

