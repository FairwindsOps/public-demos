# Running LLM Inference On Kubernetes: A Reliable Path From Cluster To First Prompt (EKS)

## Abstract

Platform and operations teams are increasingly asked to host large language model inference alongside existing applications. Kubernetes on AWS (EKS) can be a strong fit. It provides shared capacity, familiar deploy and rollout patterns, and integration with GPU instance types. Reliability, cost, and "who owns what" are typical areas of friction that can stall projects.

This 30–45 minute session is aimed at platform engineers, SREs, and engineering leaders who already know Kubernetes basics. We'll stay semi-agnostic on stacks and favor open-source patterns you can adapt, while grounding the examples in EKS and realistic CPU and GPU considerations.

We will cover a practical reliability lens: what an inference workload needs from the cluster (scheduling, resources, networking, and scaling signals), where failure modes show up, and how to keep the path to production understandable for both platform and application teams. The session includes a live demo whose end state is straightforward but concrete: a running inference endpoint on the cluster and a successful call that returns a model response so you see the full loop from deploy to usable LLM, not just a pod `Running`.

You will leave with a concise checklist for the next inference initiative on EKS and clearer language for scoping platform work versus model and application ownership.

## Short blurb

Platform-focused look at running OSS-friendly LLM inference on EKS (CPU and GPU), framed around reliability and a live demo that ends with a real prompt/response against a service in the cluster. Assumes basic Kubernetes familiarity.
