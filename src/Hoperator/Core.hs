module Hoperator.Core where

import Control.Applicative
import Control.Monad
import Control.Monad.Base
import Control.Monad.IO.Unlift (MonadIO (liftIO), MonadUnliftIO)
import Control.Monad.Reader (MonadIO, MonadPlus, MonadReader (ask), ReaderT (runReaderT))
import Control.Monad.Trans (MonadTrans)
import Data.Text
import qualified Data.Text.ANSI as A
import qualified Data.Text.IO as T
import Data.Time (getCurrentTime)
import Data.Time.Format.ISO8601 (iso8601Show)
import Kubernetes.OpenAPI
  ( KubernetesClientConfig (configHost, configValidateAuthMethods),
    KubernetesRequest,
    MimeError,
    MimeType,
    MimeUnrender,
    Produces,
    dispatchMime',
    newConfig,
  )
import Network.HTTP.Client (Manager, defaultManagerSettings, newManager)

-- * 'HoperatorEnv' and the 'HoperatorT monad transformer

--

-- $hoperatorT
--
-- The 'HoperatorT' monad transformer will serve as the execution context for your operators. It is
-- essentially a 'ReaderT' using 'HoperatorEnv' as the injected environment. 'HoperatorEnv' contains everything
-- your operators need to function, including the Http 'Manager' and the 'KubernetesClientConfig'.
data HoperatorEnv = HoperatorEnv
  { manager :: Manager
  , kubernetesClientConfig :: KubernetesClientConfig
  , logLevel :: LogLevel
  }

newtype HoperatorT m a = HoperatorT (ReaderT HoperatorEnv m a)
  deriving newtype
    ( Functor
    , Applicative
    , Monad
    , MonadIO
    , MonadReader HoperatorEnv
    , MonadTrans
    , Alternative
    , MonadPlus
    )

deriving newtype instance MonadUnliftIO m => MonadUnliftIO (HoperatorT m)
deriving newtype instance MonadBase b m => MonadBase b (HoperatorT m)

-- | The default Hoperator env assumes that the Kubernetes API is reachable on "http://localhost:8001",
-- which should be the case using `kubectl proxy`.
defaultHoperatorEnv :: MonadBase IO m => m HoperatorEnv
defaultHoperatorEnv = do
  manager <- liftBase $ newManager defaultManagerSettings
  defaultConfig <- liftBase newConfig
  let config = defaultConfig{configHost = "http://localhost:8001", configValidateAuthMethods = False}
  pure $
    HoperatorEnv
      { manager
      , kubernetesClientConfig = config
      , logLevel = Debug
      }

runHoperatorT :: HoperatorEnv -> HoperatorT m a -> m a
runHoperatorT env (HoperatorT reader) = runReaderT reader env

-- * Kubernetes client utilities

--

-- $clientUtilities
--
-- These allow you to execute kubnernetes requests in the context of 'HoperatorT'

-- | Send a request to Kubernetes, returning the decoded body or an error
runRequest ::
  (MonadBase IO m, Produces req accept, MimeUnrender accept res, MimeType contentType) =>
  KubernetesRequest req contentType res accept ->
  HoperatorT m (Either MimeError res)
runRequest req = do
  HoperatorEnv{manager, kubernetesClientConfig} <- ask
  liftBase $ dispatchMime' manager kubernetesClientConfig req

-- * Logging

--

-- $logging
--
-- 'HoperatorT' implements 'MonadLog', a simple logging class that lets you log
-- messages from your operators. Hoperator itself uses it to print useful information.

data LogLevel
  = Trace
  | Debug
  | Info
  | Warn
  | Error
  deriving (Eq, Show, Enum, Bounded, Ord)

class MonadLog m where
  logMsg :: LogLevel -> Text -> m ()

-- | Turns the 'LogLevel' into 'Text'
displayLogLevel :: LogLevel -> Text
displayLogLevel Trace = "TRACE"
displayLogLevel Debug = "DEBUG"
displayLogLevel Info = "INFO"
displayLogLevel Warn = "WARN"
displayLogLevel Error = "ERROR"

-- | Colorizes the text according to the 'LogLevel'
-- * Debug / Trace: White
-- * Info: Blue
-- * Warn: Yellow
-- * Error: Red
colorizeText :: LogLevel -> Text -> Text
colorizeText Error = A.red
colorizeText Warn = A.yellow
colorizeText Info = A.blue
colorizeText _ = A.white

instance MonadIO m => MonadLog (HoperatorT m) where
  logMsg lvl msg = do
    HoperatorEnv{logLevel} <- ask
    t <- liftIO getCurrentTime
    let formattedMsg = (pack . iso8601Show $ t) <> " - " <> displayLogLevel lvl <> " - " <> msg
    when (lvl >= logLevel) $ liftIO . T.putStrLn . colorizeText lvl $ formattedMsg

-- | Logs a message using the 'Trace' level
lTrace :: MonadLog m => Text -> m ()
lTrace = logMsg Trace

-- | Logs a message using the 'Debug' level
lDebug :: MonadLog m => Text -> m ()
lDebug = logMsg Debug

-- | Logs a message using the 'Info' level
lInfo :: MonadLog m => Text -> m ()
lInfo = logMsg Info

-- | Logs a message using the 'Warn' level
lWarn :: MonadLog m => Text -> m ()
lWarn = logMsg Warn

-- | Logs a message using the 'Error' level
lError :: MonadLog m => Text -> m ()
lError = logMsg Error