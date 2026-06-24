helm repo add kubeai https://www.kubeai.org
helm repo update

helm upgrade --install kubeai kubeai/kubeai \
    -f values.yaml \
    --set secrets.huggingface.token=$HUGGING_FACE_TOKEN \
    --namespace kai \
    --create-namespace \
    --wait

helm upgrade --install prometheus prometheus-community/kube-prometheus-stack -f prometheus.values.yaml
