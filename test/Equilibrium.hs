{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE GADTs                 #-}
{-# LANGUAGE AllowAmbiguousTypes #-}


module Equilibrium where 

import ChainEquilibrium

import           Test.QuickCheck

main = do
  verboseCheck prop_eqForallInitialChains

