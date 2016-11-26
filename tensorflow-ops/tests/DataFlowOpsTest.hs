-- Copyright 2016 TensorFlow authors.
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

{-# LANGUAGE ScopedTypeVariables #-}

import Control.Monad.IO.Class (liftIO)
import Data.Int (Int32, Int64)
import Data.List (genericLength)
import Google.Test (googleTest)
import Test.Framework.Providers.QuickCheck2 (testProperty)
import Test.HUnit ((@=?))
import Test.QuickCheck (Arbitrary(..), Property, choose, vectorOf)
import Test.QuickCheck.Monadic (monadicIO, run)

import qualified Data.Vector as V
import qualified TensorFlow.GenOps.Core as CoreOps
import qualified TensorFlow.Ops as TF
import qualified TensorFlow.Session as TF
import qualified TensorFlow.Tensor as TF
import qualified TensorFlow.Types as TF
import qualified TensorFlow.Build as TF

-- DynamicSplit is undone with DynamicStitch to get the original input
-- back.
testDynamicPartitionStitchInverse :: forall a.
    (TF.TensorType a, Show a, Eq a) => StitchExample a -> Property
testDynamicPartitionStitchInverse (StitchExample numParts values partitions) =
   let splitParts :: TF.Expr [TF.Tensor TF.Value a] =
           CoreOps.dynamicPartition numParts (TF.vector values) partTensor
       partTensor = TF.vector partitions
       restitchIndices = CoreOps.dynamicPartition numParts
                             (TF.vector [0..genericLength values-1])
                             partTensor
       -- drop (numParts - 2) from both args to expose b/27343984
       restitch = CoreOps.dynamicStitch restitchIndices splitParts
    in monadicIO $ run $ TF.runSession $ do
       sp <- TF.build $ TF.expr splitParts
       liftIO $ fromIntegral numParts @=? length sp
       valuesOut <- TF.buildAnd TF.run restitch
       liftIO $ V.fromList values @=? valuesOut

data StitchExample a = StitchExample Int64 [a] [Int32]
    deriving Show

instance Arbitrary a => Arbitrary (StitchExample a) where
    arbitrary = do
        -- Limits the size of the vector.
        size <- choose (1, 100)
        values <- vectorOf size arbitrary
        numParts <-  choose (2, 15)
        partitions <- vectorOf size (choose (0, fromIntegral numParts - 1))
        return $ StitchExample numParts values partitions

main :: IO ()
main = googleTest
       [ testProperty "DynamicPartitionStitchInverse"
         (testDynamicPartitionStitchInverse :: StitchExample Int64 -> Property)
       ]
