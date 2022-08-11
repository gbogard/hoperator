import Test.Tasty
import HoperatorTests.Watcher

main :: IO ()
main = defaultMain allTests

allTests :: TestTree
allTests = testGroup "Tests" [watcherTests]
