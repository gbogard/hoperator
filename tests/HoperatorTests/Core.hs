module HoperatorTests.Core where

import Control.Monad.Catch
import Control.Monad.Trans
import Data.Foldable (traverse_)
import Data.Time (UTCTime, getCurrentTime)
import Hoperator
import Kubernetes.OpenAPI
import Kubernetes.OpenAPI.API.BatchV1 (createNamespacedJob, deleteNamespacedJob)
import Optics.Core
import Data.Text (pack)

runHoperatorT' :: IO HoperatorEnv -> HoperatorT IO a -> IO a
runHoperatorT' envIO program = envIO >>= \env -> runHoperatorT env program

-- | Generates n jobs, inserts them into Kubernetes, then deletes then after the action is done
withJobs :: Int -> ([V1Job] -> HoperatorT IO a) -> HoperatorT IO a
withJobs n = bracket (insertJobs n) (traverse_ releaseJob)
  where
    -- insert n jobs
    insertJobs n = do
      time <- lift getCurrentTime
      let resources = buildJob time <$> [0 .. n]
      traverse_ insertJob resources
      pure resources
    -- insert a single job
    insertJob job =
      runRequest $
        createNamespacedJob (ContentType MimeJSON) (Accept MimeJSON) job (Namespace "default")
    -- build a single job
    buildJob time i =
      let
        name = pack $ show time <> "-" <> show i
        meta = mkV1ObjectMeta { v1ObjectMetaName = Just name }
        container = mkV1Container "hello-world"
        podSpec = mkV1PodSpec [container]
        podTemplateSpec = mkV1PodTemplateSpec { v1PodTemplateSpecSpec = Just podSpec }
        spec = mkV1JobSpec podTemplateSpec
      in mkV1Job { v1JobSpec = Just spec, v1JobMetadata = Just meta }
    -- release a single job
    releaseJob job =
      let name = job ^? to v1JobMetadata % _Just % to v1ObjectMetaClusterName % _Just % to Name
          req = flip (deleteNamespacedJob (ContentType MimeJSON) (Accept MimeJSON)) (Namespace "default") <$> name
       in traverse_ runRequest req