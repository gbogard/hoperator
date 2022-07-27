import Control.Monad.IO.Class
import Data.Aeson.Encode.Pretty (encodePretty)
import qualified Data.ByteString.Lazy.Char8 as BS
import Data.Text (pack)
import Hoperator.Core
import Kubernetes.OpenAPI
import Kubernetes.OpenAPI.API.BatchV1

main :: IO ()
main = do
  hoperatorEnv <- defaultHoperatorEnv
  runHoperatorT hoperatorEnv program

program :: HoperatorT IO ()
program = do
  let req = listJobForAllNamespaces (Accept MimeJSON)

  lInfo "Listing jobs in all namespaces:"
  res <- runRequest req
  case res of
    Right jobs -> liftIO . BS.putStrLn $ encodePretty jobs
    Left err -> lError . pack . show $ err