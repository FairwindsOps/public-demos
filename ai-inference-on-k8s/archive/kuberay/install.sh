helm repo add kuberay https://ray-project.github.io/kuberay-helm/
helm repo update
# Install both CRDs and KubeRay operator v1.6.0.
helm upgrade --install kuberay-operator kuberay/kuberay-operator --namespace kuberay --create-namespace --values kuberay.values.yaml
kubectl create secret generic --from-literal hf_token=$HUGGING_FACE_TOKEN hf-token --namespace kuberay
