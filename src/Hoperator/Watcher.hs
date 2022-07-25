module Hoperator.Watcher
  ( watchStream,
  )
where

import Control.Monad.Base (MonadBase (liftBase))
import Control.Monad.IO.Unlift
import Control.Monad.Reader
  ( MonadReader (ask),
    MonadTrans (lift),
    void,
  )
import Data.Aeson
import Data.JsonStream.Parser (ParseOutput (..))
import qualified Data.JsonStream.Parser as J
import Hoperator.Core
import Kubernetes.Client (WatchEvent, dispatchWatch)
import Kubernetes.OpenAPI
import Streaming
import Streaming.ByteString
import qualified Streaming.ByteString.Char8 as Q
import qualified Streaming.Prelude as S

type Closure m res done = Stream (Of (WatchEvent res)) (HoperatorT m) (Maybe String) -> HoperatorT m done

{- | Performs an action using a stream of events.
 The stream is acquired by dispatching a call to the K8s API, using the "watch" parameter.
 The resulting HTTP connection, and thus stream, will be kept active as long as the provided action/closure hasn't returned.
-}
watchStream ::
  forall req res contentType done m.
  (HasOptionalParam req Watch, MonadUnliftIO m, FromJSON res, MimeType contentType) =>
  Closure m res done ->
  KubernetesRequest req contentType res MimeJSON ->
  HoperatorT m done
watchStream closure req = do
  HoperatorEnv{manager, kubernetesClientConfig} <- ask
  withRunInIO $ \run ->
    dispatchWatch manager kubernetesClientConfig req $ \bs ->
      run . wrapClosureWithLogs closure . hoist liftIO $ streamParse J.value bs

wrapClosureWithLogs :: MonadUnliftIO m => Closure m res done -> Closure m res done
wrapClosureWithLogs closure str = do
  liftIO . putStrLn $ "[DEBUG] Acquiring closure"
  res <- closure str
  liftIO . putStrLn $ "[DEBUG] Closing closure"
  pure res

streamParse ::
  (Monad m) =>
  J.Parser a ->
  ByteStream m r ->
  Stream (Of a) m (Maybe String)
streamParse parser input = loop input (J.runParser parser)
  where
    loop bytes p0 = case p0 of
      ParseFailed err -> return $ Just err
      ParseDone bs -> return Nothing
      ParseYield a p1 -> S.yield a >> loop bytes p1
      ParseNeedData f -> do
        e <- lift $ unconsChunk bytes
        case e of
          Left r -> return $ Just "Not enough data"
          Right (bs, rest) -> loop rest (f bs)