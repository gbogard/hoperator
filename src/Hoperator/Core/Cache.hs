module Hoperator.Core.Cache
  ( Cache,
    Key,
    empty,
    mkKey,
    lookupResourceVersion,
    lookupResourceVersion',
    putResourceVersion,
    putResourceVersion',
  )
where

import Data.ByteString ( ByteString )
import Data.ByteString.Lazy (toStrict)
import qualified Data.HashMap.Strict as HM
import Data.Hashable
import Data.Text (Text)
import Kubernetes.OpenAPI

-- | A map that associates 'KubernetesRequest's with thei latest 'ResourceVersion'.
-- This enables efficient detection of changes by watching only from the last seen version and
-- listing all resources only as a last resort.
newtype Cache = Cache (HM.HashMap Key ResourceVersion)

newtype Key = Key [ByteString]
  deriving newtype (Eq, Show, Hashable)

-- | Build a new empty cache
empty :: Cache
empty = Cache HM.empty

putResourceVersion :: Cache -> KubernetesRequest req contentType resp accept -> ResourceVersion -> Cache
putResourceVersion cache req = putResourceVersion' cache (mkKey req)

putResourceVersion' :: Cache -> Key -> ResourceVersion -> Cache
putResourceVersion' (Cache hm) k version = Cache $ HM.insert k version hm

lookupResourceVersion :: Cache -> KubernetesRequest req contentType resp accept -> Maybe ResourceVersion
lookupResourceVersion cache req = lookupResourceVersion' cache $ mkKey req

lookupResourceVersion' :: Cache -> Key -> Maybe ResourceVersion
lookupResourceVersion' (Cache hm) key = HM.lookup key hm

mkKey :: KubernetesRequest req contentType resp accept -> Key
mkKey req = Key (rMethod req : (fmap toStrict . rUrlPath $ req))