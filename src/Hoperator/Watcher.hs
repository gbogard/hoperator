module Hoperator.Watcher
  ( Closure,
    listStream,
    watchStream,
    watchStreamFromLatestResourceVersion,
    listThenWatchStream,
  )
where

import Control.Concurrent
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
import Kubernetes.Client (dispatchWatch)
import Kubernetes.OpenAPI
import Streaming
import Streaming.ByteString (ByteStream)
import qualified Streaming.ByteString.Char8 as Q
import qualified Streaming.Prelude as S

data WatchEvent t = WatchEvent
  { eventType :: Text
  , eventObject :: t
  }
  deriving (Eq, Show)

instance FromJSON t => FromJSON (WatchEvent t) where
  parseJSON (Object x) = WatchEvent <$> x .: "type" <*> x .: "object"
  parseJSON _ = fail "Expected an object"

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
  , MonadIO m
  , FromJSON singleItem
  , MimeType contentType
  ) =>
  -- | A Proxy that indicates the expected type of single elements in the stream so we can determine the correct JSON decoder
  Proxy singleItem ->
  -- | The 'KubernetesRequest'
  KubernetesRequest req contentType resp MimeJSON ->
  -- | Access the stream from within the closure and implement your logic here. The HTTP connection will be discarded once the
  -- closure returns. It is possible never to return so items are watched for the entire lifetime of the program.
  Closure m singleItem done ->
  HoperatorT m done
watchStream proxy req closure = do
  let closureWithLogs = wrapClosureWithLogs (pack . show $ req) closure
  signalMVar <- liftIO newEmptyMVar
  let stream = watchStreamUnsafe proxy signalMVar req
  closure stream <* liftIO (putMVar signalMVar ())

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
  watchStream p reqWithVersion closure

-- | The "watch-then-stream" pattern returns a stream of all resources that match the request
-- by calling 'listStream', and then streams all subsequent changes to these resources.
-- * Like 'listStream', resources are internally chunked using the configured chunkSize
-- * Like 'watchStream', the underlying HTTP connection will be kept open for as long as your closure doesn't return
-- * Like 'watchStreamFromLatestResourceVersion', the "watch" part after the "list" part only returns updates since the latest
-- observed 'ResourceVersion'
listThenWatchStream ::
  forall req resp contentType singleItem done m.
  ( MonadUnliftIO m
  , Produces req MimeJSON
  , MimeUnrender MimeJSON resp
  , MimeType contentType
  , HasOptionalParam req Limit
  , HasOptionalParam req Continue
  , HasOptionalParam req Watch
  , HasOptionalParam req ResourceVersion
  , FromJSON singleItem
  ) =>
  -- | extracts metadata from the response
  (resp -> Maybe V1ListMeta) ->
  -- | extracts a list of items from the response
  (resp -> [singleItem]) ->
  -- | The 'KubernetesRequest'
  KubernetesRequest req contentType resp MimeJSON ->
  -- | Access the stream from within the closure and implement your logic here. The HTTP connection will be discarded once the
  -- closure returns. It is possible never to return so items are watched for the entire lifetime of the program.
  Closure m singleItem done ->
  HoperatorT m done
listThenWatchStream extractMeta extractItems req closure = do
  signalMVar <- liftIO newEmptyMVar
  let stream = do
        listStream extractMeta extractItems req & S.map (WatchEvent "Modified")
        version <- lift $ lookupResourceVersion req
        let watchReq = case version of
              Just v -> req -&- v
              Nothing -> req
        watchStreamUnsafe (Proxy @singleItem) signalMVar watchReq
  closure stream <* liftIO (putMVar signalMVar ())

wrapClosureWithLogs :: MonadIO m => Text -> Closure m item done -> Closure m item done
wrapClosureWithLogs ctx closure str = do
  lTrace $ "Hoperator.Watcher: Acquiring stream (" <> ctx <> ")"
  result <- closure str
  lTrace $ "Hoperator.Watcher: Closing stream (" <> ctx <> ")"
  pure result

byteStreamToEventStream ::
  forall m a.
  (MonadIO m, FromJSON a) =>
  ByteStream m () ->
  Stream (Of a) m ()
byteStreamToEventStream bs =
  Q.lines bs
    & S.mapped Q.toLazy
    & S.mapM (\res -> liftIO (print res) >> pure res)
    & S.map eitherDecode'
    & S.mapMaybeM
      ( \case
          Right a -> pure $ Just a
          Left err -> liftIO (print err) $> Nothing
      )

-- | Watches resources in the background using the provided request.
-- The HTTP connection will be kept open for as long as the provided 'MVar' remains empty
watchStreamUnsafe ::
  forall req resp contentType singleItem done m.
  ( HasOptionalParam req Watch
  , MonadIO m
  , FromJSON singleItem
  , MimeType contentType
  ) =>
  -- | A Proxy that indicates the expected type of single elements in the stream so we can determine the correct JSON decoder
  Proxy singleItem ->
  MVar () ->
  -- | The 'KubernetesRequest'
  KubernetesRequest req contentType resp MimeJSON ->
  Stream (Of (WatchEvent singleItem)) (HoperatorT m) ()
watchStreamUnsafe _ signalMVar req = do
  HoperatorEnv{manager, kubernetesClientConfig} <- ask
  streamMVar <- liftIO $ newEmptyMVar @(Stream (Of (WatchEvent singleItem)) (HoperatorT m) ())
  let closure bs = do
        let stream = hoist liftIO $ byteStreamToEventStream bs
        putMVar streamMVar stream
        readMVar signalMVar
  threadId <- liftIO . forkIO $ dispatchWatch manager kubernetesClientConfig req closure
  lift . lDebug $
    "Hoperator.Watcher.watchStreamUnsafe: Began watching using Thread ["
      <> (pack . show $ threadId)
      <> "] and request: "
      <> (pack . show $ req)
  join . liftIO $ readMVar streamMVar