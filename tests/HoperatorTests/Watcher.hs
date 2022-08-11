module HoperatorTests.Watcher (watcherTests) where

import Hoperator
import HoperatorTests.Core
import Test.Tasty
import Test.Tasty.HUnit

watcherTests :: TestTree
watcherTests =
  withResource defaultHoperatorEnv (const $ pure ()) $ \env ->
    testGroup
      "Watcher"
      [ testWatch env
      , testListThenWatch env
      , testWatchWithResourceVersionFailure env
      , testWatchWithNetworkFailure env
      , testListWithNetworkFailure env
      ]

testWatch env = testCase "Hoperator.Watcher.watchStream" $
  runHoperatorT' env $ do
    undefined

testListThenWatch env = testCase "Hoperator.Watcher.listThenWatchStream" undefined

testWatchWithResourceVersionFailure env = testCase "Hoperator.Watcher.watchStream when ResourceVersion is not available" undefined

testWatchWithNetworkFailure env = testCase "Hoperator.Watcher.watchStream when network is not available" undefined

testListWithNetworkFailure env = testCase "Hoperator.Watcher.listStream when network is not available" undefined
