module HoperatorTests.Core where

import Control.Monad (void)
import Control.Monad.Catch
import Control.Monad.Trans
import Data.Foldable (traverse_)
import Data.Maybe
import Data.Text (Text, pack, replace, toLower)
import Data.Time (UTCTime, getCurrentTime)
import Hoperator
import Kubernetes.OpenAPI
import Kubernetes.OpenAPI.API.BatchV1 (createNamespacedJob, deleteNamespacedJob)
import Kubernetes.OpenAPI.API.CoreV1 (createNamespace)
import Optics.Core
import Test.Tasty

withTestResources :: (IO HoperatorEnv -> TestTree) -> TestTree
withTestResources = withResource testHoperatorEnv (const $ pure ())

testHoperatorEnv :: IO HoperatorEnv
testHoperatorEnv = do
  env <- defaultHoperatorEnv
  createTestNamespace env
  pure env

testNamespace :: Namespace
testNamespace = Namespace "hoperator-tests"

createTestNamespace :: HoperatorEnv -> IO ()
createTestNamespace env =
  let meta = mkV1ObjectMeta{v1ObjectMetaName = Just $ unNamespace testNamespace}
      namespace = V1Namespace Nothing Nothing (Just meta) Nothing Nothing
      req = createNamespace (ContentType MimeJSON) (Accept MimeJSON) namespace
   in void . runHoperatorT env . runRequest $ req

runHoperatorT' :: IO HoperatorEnv -> HoperatorT IO a -> IO a
runHoperatorT' envIO program = envIO >>= \env -> runHoperatorT env program

-- | Generates n jobs, inserts them into Kubernetes, then deletes then after the action is done
withJobs :: Int -> ([V1Job] -> HoperatorT IO a) -> HoperatorT IO a
withJobs n = bracket (insertJobs n) (traverse_ releaseJob)
  where
    -- insert n jobs
    insertJobs n = do
      time <- lift getCurrentTime
      let jobs = buildJob time <$> [1 .. n]
      traverse_ insertJob jobs
      pure jobs
    -- insert a single job
    insertJob job =
      runRequest' $ createNamespacedJob (ContentType MimeJSON) (Accept MimeJSON) job testNamespace
    -- build a single job
    buildJob time i =
      let name = slug . pack $ "test-job-" <> show i <> "-" <> show time
          meta =
            mkV1ObjectMeta
              { v1ObjectMetaName = Just name
              , v1ObjectMetaNamespace = Just $ unNamespace testNamespace
              }
          container =
            (mkV1Container "container")
              { v1ContainerImage = Just "hello-world"
              }
          podSpec =
            (mkV1PodSpec [container])
              { v1PodSpecRestartPolicy = Just "Never"
              }
          podTemplateSpec = mkV1PodTemplateSpec{v1PodTemplateSpecSpec = Just podSpec}
          spec = mkV1JobSpec podTemplateSpec
       in mkV1Job{v1JobSpec = Just spec, v1JobMetadata = Just meta}
    -- release a single job
    releaseJob job =
      let name = job ^? to v1JobMetadata % _Just % to v1ObjectMetaName % _Just % to Name
          req = flip (deleteNamespacedJob (ContentType MimeJSON) (Accept MimeJSON)) testNamespace <$> name
       in traverse_ runRequest req

getJobName :: V1Job -> Text
getJobName job =
  let ns = job ^? to v1JobMetadata % _Just % to v1ObjectMetaNamespace % _Just
      name = job ^? to v1JobMetadata % _Just % to v1ObjectMetaName % _Just
   in fromMaybe "" ns <> "/" <> fromMaybe "" name

slug :: Text -> Text
slug = toLower . replace " " "-" . replace ":" ""