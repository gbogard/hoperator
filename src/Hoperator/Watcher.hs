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
import Data.Function
import Data.Functor
import Hoperator.Core
import Kubernetes.Client (WatchEvent, dispatchWatch)
import Kubernetes.OpenAPI
import Streaming
import Streaming.ByteString
import qualified Streaming.ByteString.Char8 as Q
import qualified Streaming.Prelude as S
import Data.Data

type Closure m item done = Stream (Of (WatchEvent item)) (HoperatorT m) () -> HoperatorT m done

{- | Performs an action using a stream of events.
 The stream is acquired by dispatching a call to the K8s API, using the "watch" parameter.
 The resulting HTTP connection, and thus stream, will be kept active as long as the provided action/closure hasn't returned.
-}
watchStream ::
  forall req resp singleItem contentType done m.
  (HasOptionalParam req Watch, MonadUnliftIO m, FromJSON singleItem, MimeType contentType) =>
  Proxy singleItem ->
  Closure m singleItem done ->
  KubernetesRequest req contentType resp MimeJSON ->
  HoperatorT m done
watchStream _ closure req = do
  HoperatorEnv{manager, kubernetesClientConfig} <- ask
  withRunInIO $ \toIO ->
    dispatchWatch manager kubernetesClientConfig req $ \bs ->
      toIO . closure . hoist liftIO $ streamParse bs

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
