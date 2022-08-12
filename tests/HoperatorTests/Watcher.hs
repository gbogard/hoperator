module HoperatorTests.Watcher (watcherTests) where

import Control.Monad (join)
import Control.Monad.Trans
import Data.Function
import qualified Data.HashSet as Set
import Hoperator
import qualified Hoperator.Watcher as W
import HoperatorTests.Core
import Kubernetes.OpenAPI
import Kubernetes.OpenAPI.API.BatchV1
import qualified Streaming.Prelude as S
import Test.Tasty
import Test.Tasty.HUnit

watcherTests :: TestTree
watcherTests = withTestResources $ \env ->
  testGroup
    "Watcher"
    [ testListStream env
    , testListThenWatch env
    , testWatchWithResourceVersionFailure env
    , testWatchWithNetworkFailure env
    , testListWithNetworkFailure env
    ]

-- | Inserts many jobs, then executes 'Hoperator.Watcher.listStream' and checks
-- that the received elements are equal to the inserted jobs
testListStream :: IO HoperatorEnv -> TestTree
testListStream env = testCase "Hoperator.Watcher.listStream" $ do
  let jobsCount = 100
  let req = listNamespacedJob (Accept MimeJSON) testNamespace
  runHoperatorT' env $
    withJobs jobsCount $ \expectedJobs -> do
      let expectedJobsNames = Set.fromList (getJobName <$> expectedJobs)
      receivedJobsNames <- takeNJobsNames jobsCount $ W.listStream v1JobListMetadata v1JobListItems req
      lift $ receivedJobsNames @?= expectedJobsNames

testListThenWatch env = testCase "Hoperator.Watcher.listThenWatchStream" undefined

testWatchWithResourceVersionFailure env = testCase "Hoperator.Watcher.watchStream when ResourceVersion is not available" undefined

testWatchWithNetworkFailure env = testCase "Hoperator.Watcher.watchStream when network is not available" undefined


-- Todo catch error
testListWithNetworkFailure env = testCase "Hoperator.Watcher.listStream when network is not available" $ do
  env >>= \e -> do
    let envWithNetworkFailure = e{kubernetesClientConfig = (kubernetesClientConfig e){configHost = "http://localhost:9096"}}
    let req = listNamespacedJob (Accept MimeJSON) testNamespace
    let stream = W.listStream v1JobListMetadata v1JobListItems req
    runHoperatorT envWithNetworkFailure (S.effects stream)

takeNJobsNames jobsCount stream =
  stream
    & S.take jobsCount
    & S.map (Set.singleton . getJobName)
    & S.mconcat_