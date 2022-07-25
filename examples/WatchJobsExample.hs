import Data.Function
import Hoperator.Core
import Hoperator.Watcher
import Kubernetes.OpenAPI
import Kubernetes.OpenAPI.API.BatchV1
import Streaming
import qualified Streaming.Prelude as S

main :: IO ()
main = do
  hoperatorEnv <- defaultHoperatorEnv
  let req = (listJobForAllNamespaces (Accept MimeJSON))

  putStrLn "Subscribing to Jobs in all namespaces"
  putStrLn "Detected job changes:"
  runHoperatorT hoperatorEnv . void . watchStream S.print $ req
    