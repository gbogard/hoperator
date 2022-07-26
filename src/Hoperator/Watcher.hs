module Hoperator.Watcher
  ( Closure,
    watchStream,
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
import Data.Data
import Data.Function
import Data.Functor
import Data.Text
import Hoperator.Core
import Kubernetes.Client (WatchEvent, dispatchWatch)
import Kubernetes.OpenAPI
import Streaming
import Streaming.ByteString (ByteStream)
import qualified Streaming.ByteString.Char8 as Q
import qualified Streaming.Prelude as S

type Closure m item done = Stream (Of (WatchEvent item)) (HoperatorT m) () -> HoperatorT m done

-- | Performs an action using a stream of events.
-- The stream is acquired by dispatching a call to the K8s API, using the "watch" parameter.
-- The resulting HTTP connection, and thus stream, will be kept active as long as the provided action/closure hasn't returned.
watchStream ::
  forall req resp singleItem contentType done m.
  (HasOptionalParam req Watch, MonadUnliftIO m, FromJSON singleItem, MimeType contentType) =>
  Proxy singleItem ->
  Closure m singleItem done ->
  KubernetesRequest req contentType resp MimeJSON ->
  HoperatorT m done
watchStream _ closure req = do
  let closureWithLogs = wrapClosureWithLogs (pack . show $ req) closure
  HoperatorEnv{manager, kubernetesClientConfig} <- ask
  withRunInIO $ \toIO ->
    dispatchWatch manager kubernetesClientConfig req $ \bs ->
      toIO . closureWithLogs . hoist liftIO $ streamParse bs

wrapClosureWithLogs :: MonadUnliftIO m => Text -> Closure m item done -> Closure m item done
wrapClosureWithLogs ctx closure str = do
  lTrace $ "Hoperator.Watcher: Acquiring stream (" <> ctx <> ")"
  result <- closure str
  lTrace $ "Hoperator.Watcher: Closing stream (" <> ctx <> ")"
  pure result

streamParse ::
  forall m a.
  (MonadUnliftIO m, FromJSON a) =>
  ByteStream m () ->
  Stream (Of a) m ()
streamParse bs =
  Q.lines bs
    & S.mapped Q.toLazy
    & S.mapM (\res -> liftIO (print res) >> pure res)
    & S.map eitherDecode'
    & S.mapMaybeM
      ( \case
          Right a -> pure $ Just a
          Left err -> liftIO (print err) $> Nothing
      )
