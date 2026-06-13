# AWS Autoscaling & Chaos Engineering Platform

## Overview

This project is a hands-on platform engineering lab designed to explore how modern cloud-native systems behave under scale, failure, and extreme traffic conditions.

The goal is not simply to configure an autoscaler. The goal is to understand the real challenges faced by large-scale platforms during events such as IPL finals, Black Friday sales, product launches, flash sales, and unexpected traffic spikes.

By the end of the project we will simulate and recover from scenarios involving:

- Rapid traffic growth
- Pod and node autoscaling
- Spot instance interruptions
- Availability Zone failures
- Subnet IP exhaustion
- NAT Gateway failures
- Load balancer saturation
- Elevated 5xx error rates
- DDoS-like traffic patterns
- Multi-region failover
- CDN and latency-based routing

---

# Learning Objectives

Most engineers learn:

CPU > 70% → Add More Servers

Real platforms scale based on much more than CPU.

This project explores scaling based on:

- Concurrent users
- Active WebSocket connections
- Request rate
- Queue depth
- Response latency
- Error rate
- Pending Kubernetes pods
- Available IP addresses
- Spot market capacity
- Regional traffic distribution

The project intentionally recreates real-world bottlenecks that occur long before CPU becomes the limiting factor.

---

# Current Project State

Completed:

✅ Terraform Remote State

✅ VPC

✅ Public Subnets

✅ Private Subnets

✅ NAT Gateway

✅ EKS Control Plane

✅ Managed Node Group

✅ OIDC Provider

✅ KMS Encryption

✅ VPC CNI

✅ kube-proxy

✅ CoreDNS

✅ Git Repository Structure

---

# Phase 1 – Terraform Remote State

Completed.

## Resources Created

- S3 Bucket for Terraform State
- DynamoDB Table for Terraform State Locking

## Why?

Terraform state is critical infrastructure.

Without remote state:

- Multiple engineers can overwrite changes
- State can be lost if a laptop is replaced
- Infrastructure drift becomes difficult to detect

The S3 + DynamoDB pattern is the industry-standard Terraform backend architecture.

## Resources

Terraform State Bucket:

aws-autoscaling-chaos-platform-tfstate-974318644331

Terraform Lock Table:

aws-autoscaling-chaos-platform-locks

---

# Phase 2 – Network Foundation

Completed.

## VPC Architecture

Region:

ap-south-1

Availability Zones:

ap-south-1a
ap-south-1b
ap-south-1c

VPC CIDR:

10.0.0.0/16

---

## Public Subnets

10.0.0.0/24
10.0.1.0/24
10.0.2.0/24

Purpose:

- Internet-facing Load Balancers
- NAT Gateway

---

## Private Subnets

10.0.16.0/20
10.0.32.0/20
10.0.48.0/20

Purpose:

- Kubernetes worker nodes
- Application workloads
- Internal services

---

## Why Large Private Subnets?

One of the future chaos experiments is subnet IP exhaustion.

Many production outages happen because:

Cluster has CPU

Cluster has Memory

But

No IP addresses remain

Using dedicated private subnets allows us to later:

- Simulate IP exhaustion
- Measure pod scheduling failures
- Explore mitigation strategies

---

## NAT Gateway Design

Current Design:

Single NAT Gateway

This is intentional.

Many tutorials recommend maximum redundancy immediately.

This project intentionally starts with a simpler design to allow us to demonstrate:

- NAT Gateway dependency
- Outbound connectivity failures
- Image pull failures
- Node bootstrap failures
- Recovery strategies

Future experiments will compare:

Single NAT vs NAT Per AZ

and evaluate the cost vs resiliency tradeoff.

---

## Karpenter Discovery Tags

Subnets are tagged for future Karpenter integration.

karpenter.sh/discovery=autoscaling-chaos-dev

These tags allow Karpenter to discover where it can provision capacity.

---

# Phase 3 – EKS Cluster Deployment

Completed.

## Cluster Configuration

Cluster Name:

autoscaling-chaos-dev

Kubernetes Version:

1.32

Region:

ap-south-1

---

## Bootstrap Node Group

Purpose:

Provide the initial compute capacity required to run cluster services and future platform components.

Configuration:

Instance Type: t4g.large

Architecture: ARM64

Operating System: Amazon Linux 2023

Desired Capacity: 2

Minimum Capacity: 2

Maximum Capacity: 4

---

## Why Not Start With Karpenter?

A common mistake is trying to build:

EKS + Karpenter

with no worker nodes.

Karpenter itself runs as pods.

Pods require nodes.

This creates a bootstrap dependency problem:

Karpenter needs nodes

Nodes need Karpenter

To solve this:

Managed Node Group
→ Hosts Karpenter
→ Karpenter Creates Additional Nodes

This mirrors production deployments used by many organizations.

---

# Security Decisions

## Kubernetes Secret Encryption

Enabled using customer-managed KMS keys.

Purpose:

- Encrypt Kubernetes secrets at rest
- Align with production security practices

---

## IAM Roles for Service Accounts (IRSA)

OIDC provider created successfully.

This enables:

- AWS Load Balancer Controller
- Karpenter
- ExternalDNS
- OpenTelemetry

to access AWS APIs without storing credentials inside pods.

---

# Phase 4 – EKS Bootstrap Failure Investigation

Completed.

This phase exposed a real-world EKS bootstrap issue that is commonly encountered when deploying production clusters.

---

## Initial Symptoms

Terraform reported:

NodeCreationFailure

and the Managed Node Group entered:

CREATE_FAILED

after approximately 30 minutes.

However:

- EKS Control Plane was ACTIVE
- EC2 instances were running
- Nodes appeared inside Kubernetes

This indicated the failure was occurring after node launch.

---

## Investigation

Cluster Status:

aws eks describe-cluster

Result:

ACTIVE

Node Status:

kubectl get nodes

Result:

Nodes were present but remained NotReady.

Further inspection:

kubectl describe node

showed:

NetworkPluginNotReady

cni plugin not initialized

Checking cluster workloads:

kubectl get pods -A

returned:

No resources found

Checking EKS managed addons:

aws eks list-addons

returned:

[]

No addons were installed.

---

## Root Cause

The cluster was missing the required EKS managed addons:

- VPC CNI
- kube-proxy
- CoreDNS

Without VPC CNI:

- Pod networking cannot initialize
- Nodes remain NotReady
- Managed Node Group creation eventually fails

The worker nodes themselves were healthy.

The Kubernetes networking layer never became operational.

---

## Resolution

Installed required EKS managed addons manually.

VPC CNI:

aws eks create-addon --addon-name vpc-cni

kube-proxy:

aws eks create-addon --addon-name kube-proxy

CoreDNS:

aws eks create-addon --addon-name coredns

After the addons became ACTIVE:

kubectl get nodes

returned:

Ready

Core Kubernetes services immediately started successfully.

---

## Validation

Healthy Cluster State:

Nodes:

2 Ready Nodes

System Pods:

- aws-node
- kube-proxy
- CoreDNS

All Running Successfully.

---

## Lessons Learned

A worker node can successfully join an EKS cluster while still remaining NotReady.

When troubleshooting EKS bootstrap failures, always inspect:

- kubectl get nodes
- kubectl describe node
- kubectl get pods -A
- aws eks list-addons

before assuming the issue is related to:

- IAM
- Security Groups
- Routing
- NAT Gateway
- VPC Configuration

This troubleshooting exercise provided practical experience with how EKS worker nodes, networking, and managed addons interact during cluster initialization.

---

# Current Running Infrastructure

Region:

ap-south-1

Cluster:

autoscaling-chaos-dev

Nodes:

2 x t4g.large

Node Status:

Ready

Core Addons:

- VPC CNI
- kube-proxy
- CoreDNS

Terraform Backend:

Operational

VPC:

Operational

OIDC Provider:

Operational

KMS Encryption:

Operational

---

# Upcoming Phases

## Phase 5 – Core Platform Components

- Metrics Server
- AWS Load Balancer Controller
- Karpenter

---

## Phase 6 – Autoscaling

- Horizontal Pod Autoscaler (HPA)
- KEDA
- Request-based scaling
- Connection-based scaling

---

## Phase 7 – Spot Capacity Engineering

- Mixed instance types
- Spot interruption handling
- Capacity shortages
- Fallback strategies

---

## Phase 8 – Chaos Engineering

- Node failures
- Spot interruptions
- NAT failures
- Subnet exhaustion
- ALB failures
- Elevated 5xx responses

---

## Phase 9 – Large Event Simulation

Simulate traffic patterns similar to:

- IPL Final
- Flash Sale
- Product Launch

while measuring:

- Scaling speed
- Error rate
- Latency
- Recovery time

---

## Phase 10 – Multi-Region Platform

- Multi-region EKS deployment
- Route53 latency routing
- Regional failover
- Cross-region resilience testing

---

## Phase 11 – Global Platform Design

- CDN integration
- Edge optimization
- Global traffic steering
- Worldwide failover architecture

---

# Key Lesson

The biggest lesson of this project so far is:

Autoscaling is often not the difficult part.

The difficult part is finding capacity and maintaining platform dependencies when everything is under pressure.

During major events:

- Spot inventory may be unavailable
- Specific instance families may be constrained
- Entire Availability Zones may be under pressure
- Network limits may be reached
- IP address exhaustion may occur
- Critical platform components may fail before applications fail

Designing for those realities is what separates a resilient platform from a platform that merely has an autoscaler configured.