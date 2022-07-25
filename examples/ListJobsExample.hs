import Data.Aeson.Encode.Pretty (encodePretty)
import Data.Function
import Hoperator.Core
import Kubernetes.OpenAPI
import Kubernetes.OpenAPI.API.BatchV1
import Streaming
import qualified Streaming.Prelude as S
import qualified Data.ByteString.Lazy.Char8 as BS

main :: IO ()
main = do
  hoperatorEnv <- defaultHoperatorEnv
  putStrLn "Listing jobs:"
  let req = (listJobForAllNamespaces (Accept MimeJSON))
  res <- runHoperatorT hoperatorEnv (runRequest req)
  case res of
    Right jobs -> BS.putStrLn $ encodePretty jobs
    Left err -> putStrLn "ERROR:" >> print err