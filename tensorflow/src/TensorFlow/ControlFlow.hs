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

-- TODO: we should use OpGen for most of this

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module TensorFlow.ControlFlow
    ( -- * Dependencies
      withControlDependencies
    , group
      -- * Operations
    , identity
    , noOp
    , named
    ) where

import qualified Data.Set as Set
import Data.Text (Text)
import Lens.Family2 ((&), (^.), (.~))

import TensorFlow.BuildOp
import TensorFlow.Build
import TensorFlow.Nodes
import TensorFlow.Output
import TensorFlow.Tensor
import TensorFlow.Types

-- | Modify a 'Build' action, such that all new ops rendered in it will depend
-- on the nodes in the first argument.
withControlDependencies :: Nodes t => t -> Build a -> Build a
withControlDependencies deps act = withNodeDependencies (nodes deps) act

-- TODO(judahjacobson): Reimplement withDependencies.

-- | Create an op that groups multiple operations.
--
-- When this op finishes, all ops in the input @n@ have finished.  This op has
-- no output.
group :: Nodes t => t -> Build ControlNode
group deps = buildOp []
                $ opDef "NoOp" & opControlInputs .~ Set.toList (nodes deps)


-- | Returns a 'Tensor' with the same shape and contents as the input.
identity :: TensorType a => Tensor v a -> TensorExpr a
identity = namedIdentity implicitName

-- TODO: replace this with just "opName".
-- | Returns a 'Tensor' with a given name and the same shape and contents as
-- the input.
--
-- TODO(judahjacobson): This breaks when used with uninitialize @Tensor Ref@s,
-- since @RefIdentity@ doesn't have SetAllowsUninitializedInput().  Look into
-- whether we can change that op.
named :: TensorType a => Text -> Tensor v a -> TensorExpr a
named = namedIdentity . explicitName

-- | An internal version of "identity" that allows setting the name
-- of the output Tensor.
namedIdentity :: forall a v . TensorType a
              => PendingNodeName -> Tensor v a -> TensorExpr a
namedIdentity n t = exprOp [] $ pure $
    let setAttr = (opAttr "T" .~ tensorType (undefined :: a))
                . (opInputs .~ [t ^. tensorOutput])
    in case t ^. tensorKind of
        ValueKind -> opDefWithName n "Identity"
                        & setAttr
        RefKind -> opDefWithName n "RefIdentity"
                        & setAttr


-- | Does nothing.  Only useful as a placeholder for control edges.
noOp :: Build ControlNode
noOp = buildOp [] $ opDef "NoOp"
