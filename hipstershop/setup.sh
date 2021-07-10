echo Create namespace for sample app
kubectl create ns hipster-shop
kubectl -n hipster-shop create rolebinding default-view --clusterrole=view --serviceaccount=hipster-shop:default
echo Deploy sample app
kubectl -n hipster-shop apply -f k8s-manifest.yaml
