module Hoperator.Watcher
  ( watchStream,
  )
where

import Control.Monad.Base (MonadBase (liftBase))
import Control.Monad.Reader
    ( MonadTrans(lift), MonadReader(ask), void )
import Data.Aeson
import Data.JsonStream.Parser (ParseOutput (..))
import qualified Data.JsonStream.Parser as J
import Hoperator.Core
import Kubernetes.Client (WatchEvent, dispatchWatch)
import Kubernetes.OpenAPI (HasOptionalParam, KubernetesRequest, MimeType, Watch)
import Streaming
import Streaming.ByteString
import qualified Streaming.Prelude as S

-- | Dispatches a watch request to the K8s API and returns events as a stream.
watchStream ::
  forall req res accept contentType m.
  (HasOptionalParam req Watch, MimeType accept, MimeType contentType, MonadBase IO m, FromJSON res) =>
  KubernetesRequest req contentType res accept ->
  Stream (Of (WatchEvent res)) (HoperatorT m) ()
watchStream req = do
  HoperatorEnv{manager, kubernetesClientConfig} <- ask
  hoist liftBase . effect $ dispatchWatch manager kubernetesClientConfig req handler
  where
    handler bs = pure . void $ streamParse parser bs
    parser = J.value

{- | Taken from streaming-utils
     This function is closely modelled on
     'Data.JsonStream.Parser.parseByteString' and
     'Data.JsonStream.Parser.parseLazyByteString' from @Data.JsonStream.Parser@.
-}
streamParse ::
  (Monad m) =>
  J.Parser a ->
  ByteStream m r ->
  Stream (Of a) m (Maybe String, ByteStream m r)
streamParse parser input = loop input (J.runParser parser)
  where
    loop bytes p0 = case p0 of
      ParseFailed s -> return (Just s, bytes)
      ParseDone bs -> return (Nothing, chunk bs >> bytes)
      ParseYield a p1 -> S.yield a >> loop bytes p1
      ParseNeedData f -> do
        e <- lift $ unconsChunk bytes
        case e of
          Left r -> return (Just "Not enough data", return r)
          Right (bs, rest) -> loop rest (f bs)