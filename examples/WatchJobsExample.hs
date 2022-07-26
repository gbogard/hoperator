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
  let req = (listJobForAllNamespaces (Accept MimeJSON))
  let stream = watchStream (Proxy @V1Job) S.print $ req

  putStrLn "Detected job changes:"
  runHoperatorT hoperatorEnv . void $ stream
    