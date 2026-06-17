# Kubernetes Resources

This directory contains Kubernetes manifests used to validate autoscaling, node provisioning, request-based scaling, and Spot interruption scenarios.

## Structure

apps/
Production-style workloads.

ingress/
AWS ALB ingress definitions.

keda/
KEDA-based scaling configurations.

nodepools/
Karpenter NodePools and EC2NodeClasses.

validation/
Temporary workloads used to validate scaling and scheduling behavior.