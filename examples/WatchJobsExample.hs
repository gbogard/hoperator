import Data.Function
import Hoperator.Core
import Hoperator.Watcher
import Kubernetes.OpenAPI
import Kubernetes.OpenAPI.API.BatchV1
import Streaming
import Data.Data
import qualified Streaming.Prelude as S

main :: IO ()
main = do
  hoperatorEnv <- defaultHoperatorEnv
  runHoperatorT hoperatorEnv program

program :: HoperatorT IO () 
program = do
  let req = (listJobForAllNamespaces (Accept MimeJSON))

  lInfo "Subscribing to jobs in all namespaces"
  lInfo "Detected job changes:"
  watchStream (Proxy @V1Job) S.print req