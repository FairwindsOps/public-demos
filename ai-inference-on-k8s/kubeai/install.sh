#!/bin/bash

helm repo add kubeai https://www.kubeai.org
helm repo update

helm upgrade --install kubeai kubeai/kubeai \
    -f values.yaml \
    --set secrets.huggingface.token=$HUGGING_FACE_TOKEN \
    --namespace kai \
    --create-namespace \
    --wait

kubectl label namespace kai scrape=kai --overwrite
