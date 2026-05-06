#!/bin/bash

helm upgrade --install ollama otwld/ollama --namespace ollama --create-namespace --values ollama.values.yaml
