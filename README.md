<div style="text-align: center; margin-bottom: 2rem;">
<h1>Hoperator</h1>
<img src="https://github.com/gbogard/hoperator/blob/main/logo.png?raw=true" width="150px" alt="Hoperator logo" />
</div>

Hoperator (*Haskell + operator*) is a library that makes it easier to build 
[Kubernetes operators](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/) using the Haskell programming language.

It is inspired by similar libraries in other languages such as [Operator SDK](https://github.com/operator-framework/operator-sdk) for Go,
and [kube-rs](https://github.com/kube-rs/kube-rs) for Rust. Hoperator builds upon 
[the official Kubernetes client for Haskell](https://hackage.haskell.org/package/kubernetes-client) and adds change detection
mechanisms, reconcile loops, and other utilities.

## Examples

Examples are located in `examples/`. You can launch individual examples using Cabal:

```shell
kubectl proxy # Make the Kubernetes API accessible on localhost:8080

cabal run example-watch-jobs
cabal run example-list-jobs
cabal run example-list-then-watch-jobs
```

## Feature Roadmap

- Watcher: convenient and efficient detection of changes in a Kubernetes cluster (🚧 Work in progress)
- Custom resource definitions and code generation (📆 planned)
- Controllers: worker queues that processes reconcile requests efficiently (📆 planned)