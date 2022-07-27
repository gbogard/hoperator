<div style="text-align: center; margin-bottom: 2rem;">
<h1>Hoperator</h1>
<img src="https://github.com/gbogard/hoperator/blob/main/logo.png?raw=true" width="150px" alt="Hoperator logo" />
</div>


Hoperator (*Haskell + operator*) is a library that makes it easier to build [Kubernetes operators](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/) 
using the Haskell programming language.

## Examples

Examples are located in `examples/`. You can launch individual examples using Cabal:

```shell
kubectl proxy # Make the Kubernetes API accessible on localhost:8080

cabal run example-watch-jobs
cabal run example-list-jobs
cabal run example-list-then-watch-jobs
```