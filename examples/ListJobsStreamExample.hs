import Control.Monad.IO.Class
import Data.Text (pack)
import Hoperator.Core
import Hoperator.Watcher (listStream)
import Kubernetes.OpenAPI
import Kubernetes.OpenAPI.API.BatchV1
import qualified Streaming.Prelude as S

main :: IO ()
main = do
  hoperatorEnv <- defaultHoperatorEnv
  runHoperatorT hoperatorEnv program

program :: HoperatorT IO ()
program = do
  let req = listJobForAllNamespaces (Accept MimeJSON)
  let stream = listStream v1JobListMetadata v1JobListItems req

  lDebug "Listing jobs in all namespaces (using streams):"
  S.mapM_ (lInfo . pack . show) stream
