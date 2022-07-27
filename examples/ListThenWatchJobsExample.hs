import Hoperator.Core
import Hoperator.Watcher
import Kubernetes.OpenAPI
import Kubernetes.OpenAPI.API.BatchV1
import Data.Data
import qualified Streaming.Prelude as S

main :: IO ()
main = do
  hoperatorEnv <- defaultHoperatorEnv
  let env = hoperatorEnv {logLevel = Trace}
  runHoperatorT env program

program :: HoperatorT IO () 
program = do
  let req = (listJobForAllNamespaces (Accept MimeJSON))

  lInfo "Subscribing to jobs in all namespaces"
  lInfo "Detected job changes:"
  listThenWatchStream v1JobListMetadata v1JobListItems req S.print