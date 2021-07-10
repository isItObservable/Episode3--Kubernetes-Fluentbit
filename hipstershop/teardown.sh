#!/bin/sh

kubectl -n hipster-shop delete -f k8s-manifest.yaml
kubectl delete ns hipster-shop
