module Hoperator.Watcher
  ( Closure,
    listStream,
    watchStream,
    watchStreamFromLatestResourceVersion,
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

-- | Executes a Kubernetes request and returns the result as a stream of elements.
-- This internally uses the 'APIListChunking' feature of Kubernetes to retrieve the results in manageable chunks.
-- The chunk size (the "limit" parameter passed to the Kubernetes API) is configured as part of 'HoperatorEnv'
listStream ::
  forall req resp accept contentType singleItem m.
  ( MonadIO m
  , Produces req accept
  , MimeUnrender accept resp
  , MimeType contentType
  , HasOptionalParam req Limit
  , HasOptionalParam req Continue
  ) =>
  -- | extracts metadata from the response
  (resp -> Maybe V1ListMeta) ->
  -- | extracts a list of items from the response
  (resp -> [singleItem]) ->
  -- | the 'KubernetesRequest'
  KubernetesRequest req contentType resp accept ->
  Stream (Of singleItem) (HoperatorT m) ()
listStream extractMeta extractItems req = do
  HoperatorEnv{chunkSize} <- ask
  run (req -&- Limit chunkSize)
  where
    run req = do
      lift . lDebug $ "Hoperator.Watcher.listStream: Requesting " <> (pack . show $ req)
      res <- lift $ runRequest req
      case res of
        Right res -> do
          let items = extractItems res
          case extractMeta res of
            -- If this is not the last page, loop using the provided "continue" parameter
            Just m | Just continuation <- v1ListMetaContinue m -> do
              lift . lTrace $ "Hoperator.Watcher.listStream: Continuing using received continuation " <> (pack . show $ continuation)
              let reqWithContinue = req -&- Continue continuation
              S.each items >> run reqWithContinue
            -- If this is is the last page and have a 'ResourceVersion', store it in the
            -- cache to further calls to 'watchStream' are more efficient.
            Just m | Just resourceVersion <- v1ListMetaResourceVersion m -> do
              lift . lTrace $ "Hoperator.Watcher.listStream: Storing resource version " <> resourceVersion
              lift . putResourceVersion req . ResourceVersion $ resourceVersion
              S.each items
            -- If we don't have a 'ResourceVersion' to store, just return the stream
            _ -> S.each items
        Left err -> lift . lError . pack . show $ err

-- | Performs an action using a stream of events.
-- The stream is acquired by dispatching a call to the K8s API, using the "watch" parameter.
-- The resulting HTTP connection, and thus stream, will be kept active as long as the provided action/closure hasn't returned.
watchStream ::
  forall req resp contentType singleItem done m.
  ( HasOptionalParam req Watch
  , MonadUnliftIO m
  , FromJSON singleItem
  , MimeType contentType
  ) =>
  -- | A Proxy that indicates the expected type of single elements in the stream so we can determine the correct JSON decoder
  Proxy singleItem ->
  -- | Access the stream from within the closure and implement your logic here. The HTTP connection will be discarded once the
  -- closure returns. It is possible never to return so items are watched for the entire lifetime of the program.
  Closure m singleItem done ->
  -- | The 'KubernetesRequest'
  KubernetesRequest req contentType resp MimeJSON ->
  HoperatorT m done
watchStream _ closure req = do
  let closureWithLogs = wrapClosureWithLogs (pack . show $ req) closure
  HoperatorEnv{manager, kubernetesClientConfig} <- ask
  withRunInIO $ \toIO ->
    dispatchWatch manager kubernetesClientConfig req $ \bs ->
      toIO . closureWithLogs . hoist liftIO $ streamParse bs

-- | Same as 'watchStream' but also sends a 'ResourceVersion' parameter so that
-- events are only retrieved from the last seen 'ResourceVersion' according to our cache.
-- If we don't have a last 'ResourceVersion' for the request, then this function performs the same as 'watchStream'
watchStreamFromLatestResourceVersion ::
  forall req resp contentType singleItem done m.
  ( HasOptionalParam req Watch
  , HasOptionalParam req ResourceVersion
  , MonadUnliftIO m
  , FromJSON singleItem
  , MimeType contentType
  ) =>
  -- | A Proxy that indicates the expected type of single elements in the stream so we can determine the correct JSON decoder
  Proxy singleItem ->
  -- | Access the stream from within the closure and implement your logic here. The HTTP connection will be discarded once the
  -- closure returns. It is possible never to return so items are watched for the entire lifetime of the program.
  Closure m singleItem done ->
  -- | The 'KubernetesRequest'
  KubernetesRequest req contentType resp MimeJSON ->
  HoperatorT m done
watchStreamFromLatestResourceVersion p closure req = do
  version <- lookupResourceVersion req
  let reqWithVersion =
        case version of
          Just v -> req -&- v
          Nothing -> req
  watchStream p closure reqWithVersion

listThenWatchStream ::
  forall req resp contentType singleItem done m.
  ( HasOptionalParam req Watch
  , HasOptionalParam req ResourceVersion
  , MonadUnliftIO m
  , FromJSON singleItem
  , MimeType contentType
  ) =>
  -- | extracts metadata from the response
  (resp -> Maybe V1ListMeta) ->
  -- | extracts a list of items from the response
  (resp -> [singleItem]) ->
  -- | Access the stream from within the closure and implement your logic here. The HTTP connection will be discarded once the
  -- closure returns. It is possible never to return so items are watched for the entire lifetime of the program.
  Closure m singleItem done ->
  -- | The 'KubernetesRequest'
  KubernetesRequest req contentType resp MimeJSON ->
  HoperatorT m done
listThenWatchStream req

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
