{-# LANGUAGE MultiParamTypeClasses, FlexibleInstances, TemplateHaskell #-}

module OpenGames.Examples.Consensus.DepositGame where

import Control.Arrow (Kleisli(..))
import Numeric.Probability.Distribution (certainly)

import OpenGames.Preprocessor.AbstractSyntax
import OpenGames.Preprocessor.THSyntax
import OpenGames.Engine.OpenGamesClass
import OpenGames.Engine.OpticClass
import OpenGames.Engine.DecisionClass
import OpenGames.Engine.StatefulBayesian hiding (decision, roleDecision, dependentDecision)
import OpenGames.Engine.DependentDecision

generateGame "depositStagePlayer" ["name", "minDeposit", "maxDeposit", "incrementDeposit", "epsilon"] $
  block ["costOfCapital"] []
  [line [[|costOfCapital|]] [] [|epsilonDecision epsilon name [minDeposit, minDeposit + incrementDeposit .. maxDeposit]|] ["deposit"] [[|(-deposit) * costOfCapital|]]]
  [[|deposit|]] []
{-}
depositStagePlayerSrc = Block ["costOfCapital"] []
  [Line ["costOfCapital"] [] "dependentDecision name (const [minDeposit, minDeposit + incrementDeposit .. maxDeposit])" ["deposit"] ["-deposit * costOfCapital"]]
  ["deposit"] []

depositStagePlayer name minDeposit maxDeposit incrementDeposit = reindex (\x -> (x, ())) ((reindex (\x -> ((), x)) ((fromFunctions (\x -> x) (\(costOfCapital, deposit) -> ())) >>> (reindex (\a1 -> a1) (reindex (\x -> (x, ())) ((reindex (\x -> ((), x)) ((fromFunctions (\costOfCapital -> (costOfCapital, costOfCapital)) (\((costOfCapital, deposit), ()) -> (costOfCapital, deposit))) >>> (reindex (\x -> ((), x)) ((fromFunctions (\x -> x) (\x -> x)) &&& ((dependentDecision name (const [minDeposit, minDeposit + incrementDeposit .. maxDeposit]))))))) >>> (fromFunctions (\(costOfCapital, deposit) -> (costOfCapital, deposit)) (\(costOfCapital, deposit) -> ((costOfCapital, deposit), -deposit * costOfCapital)))))))) >>> (fromLens (\(costOfCapital, deposit) -> deposit) (curry (\((costOfCapital, deposit), ()) -> (costOfCapital, deposit)))))
-}
generateGame "playingStagePlayer" ["name", "moves"] $ block ["observation", "bribe"] []
  [line [[|observation|], [|bribe|]] [] [|dependentDecision name (const moves)|] ["move"] [[|payoff + if bribePaid then bribe else 0|]]]
  [[|move|]] ["payoff", "bribePaid"]

class Obfuscatable x y where
  obfuscate :: [x] -> y

instance Obfuscatable Bool [Bool] where
  obfuscate xs = if numHonest >= numCensor then replicate numPlayers True else map not xs
    where numPlayers = length xs
          numHonest = length (filter id xs)
          numCensor = length (filter not xs)

instance Obfuscatable Bool Int where
  obfuscate xs = length (filter id xs)

payoffInt :: Double -> Double -> [Double] -> Int -> [Double]
payoffInt payoffParameter reward deposits numHonest
  = if totalDeposit == 0
       then replicate (length deposits) 0
       else [(rewardShare deposit + deposit)*payoffScaler - deposit | deposit <- deposits]
  where n = fromIntegral (length deposits)
        m = fromIntegral numHonest
        totalDeposit = sum deposits
        outcomeScore = m / n
        safeDepositProportion = payoffParameter
        payoffScaler = outcomeScore*(1 - safeDepositProportion) + safeDepositProportion
        rewardShare deposit = (deposit / totalDeposit)*reward

attackerPayoff :: [Bool] -> Double -> Double -> Double
attackerPayoff bribesAccepted bribe successfulAttackPayoff
  | (numBribed == numPlayers) = successfulAttackPayoff - bribe*(fromIntegral numBribed)
  | (otherwise)               = -bribe*(fromIntegral numBribed)
  where numPlayers = length bribesAccepted
        numBribed  = length (filter id bribesAccepted)

generateGame "fullThing" ["numPlayers", "reward", "costOfCapital", "maxBribe", "successfulAttackPayoff", "payoffParameter"] $ block [] []
  [line [ [| replicate numPlayers costOfCapital |] ] ["discard1"] [| population [depositStagePlayer ("Player " ++ show n) 0 10 0.1 0.001 | n <- [1 .. numPlayers]] |] ["deposits"] [ [| replicate numPlayers () |] ],
   line [ [| deposits |] ] [] [| dependentDecision "Attacker" (const [0, 0.0025 .. maxBribe]) |] ["bribe"] [ [| attackerPayoff bribesAccepted bribe successfulAttackPayoff |] ],
   line [ [| replicate numPlayers (deposits, bribe) |] ] ["discard2"] [| population [playingStagePlayer ("Player " ++ show n) [True, False] | n <- [1 .. numPlayers]] |] ["moves"] [ [| zip (payoffInt payoffParameter reward deposits (obfuscate moves)) bribesAccepted |] ],
   line [ [| moves |] ] [] [| fromFunctions (map not) id |] ["bribesAccepted"] []]
  [] []

testFullThing numPlayers reward costOfCapital = equilibrium (fullThing numPlayers reward costOfCapital 10 1000 0) void
-- with 10 players, reward = 5, costOfCapital = 0.046

deviationPenalty i reward deposits payoffParameter = ((payoffInt payoffParameter reward deposits numPlayers) !! i)
                                   - ((payoffInt payoffParameter reward deposits (numPlayers - 1)) !! i)
  where numPlayers = length deposits

bribeStrategy i reward payoffParameter = Kleisli $ \(deposits, bribe) -> certainly $ deviationPenalty i reward deposits payoffParameter >= bribe

testBribeStrategy costOfCapital bribe payoffParameter = testFullThing numPlayers reward costOfCapital $
  (replicate numPlayers $ Kleisli $ const $ certainly 5,
   Kleisli $ const $ certainly bribe,
   [bribeStrategy i reward payoffParameter | i <- [0 .. numPlayers - 1]],
   ())
   where reward = 5
         numPlayers = 10
