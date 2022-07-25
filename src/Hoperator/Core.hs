module Hoperator.Core where

import Control.Applicative
import Control.Monad.Base
import Control.Monad.Reader (MonadIO, MonadPlus, MonadReader (ask), ReaderT (runReaderT))
import Control.Monad.Trans (MonadTrans)
import Kubernetes.OpenAPI
import Network.HTTP.Client (Manager, defaultManagerSettings, newManager)

data HoperatorEnv = HoperatorEnv
  { manager :: Manager
  , kubernetesClientConfig :: KubernetesClientConfig
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

deriving newtype instance MonadBase b m => MonadBase b (HoperatorT m)

defaultHoperatorEnv :: MonadBase IO m => m HoperatorEnv
defaultHoperatorEnv = do
  manager <- liftBase $ newManager defaultManagerSettings
  defaultConfig <- liftBase newConfig
  pure $
    HoperatorEnv
      { manager
      , kubernetesClientConfig = defaultConfig
      }

runHoperatorT :: HoperatorEnv -> HoperatorT m a -> m a
runHoperatorT env (HoperatorT reader) = runReaderT reader env

-- | Send a request to Kubernetes, returning the decoded body or an error
runRequest ::
  (MonadBase IO m, Produces req accept, MimeUnrender accept res, MimeType contentType) =>
  KubernetesRequest req contentType res accept ->
  HoperatorT m (Either MimeError res)
runRequest req = do
  HoperatorEnv{manager, kubernetesClientConfig} <- ask
  liftBase $ dispatchMime' manager kubernetesClientConfig req