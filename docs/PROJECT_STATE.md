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

text CPU > 70% → Add More Servers 

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

## Phase 1 – Terraform Remote State

Completed.

### Resources Created

- S3 Bucket for Terraform State
- DynamoDB Table for Terraform State Locking

### Why?

Terraform state is critical infrastructure.

Without remote state:

- Multiple engineers can overwrite changes
- State can be lost if a laptop is replaced
- Infrastructure drift becomes difficult to detect

The S3 + DynamoDB pattern is the industry-standard Terraform backend architecture.

### Resources

Terraform State Bucket:

text aws-autoscaling-chaos-platform-tfstate-974318644331 

Terraform Lock Table:

text aws-autoscaling-chaos-platform-locks 

---

# Phase 2 – Network Foundation

Completed.

## VPC Architecture

Region:

text ap-south-1 

Availability Zones:

text ap-south-1a ap-south-1b ap-south-1c 

VPC CIDR:

text 10.0.0.0/16 

---

## Public Subnets

text 10.0.0.0/24 10.0.1.0/24 10.0.2.0/24 

Purpose:

- Internet-facing Load Balancers
- NAT Gateway

---

## Private Subnets

text 10.0.16.0/20 10.0.32.0/20 10.0.48.0/20 

Purpose:

- Kubernetes worker nodes
- Application workloads
- Internal services

---

# Why Large Private Subnets?

One of the future chaos experiments is subnet IP exhaustion.

Many production outages happen because:

text Cluster has CPU Cluster has Memory  But  No IP addresses remain 

Using dedicated private subnets allows us to later:

- Simulate IP exhaustion
- Measure pod scheduling failures
- Explore mitigation strategies

---

# NAT Gateway Design

Current Design:

text Single NAT Gateway 

This is intentional.

Many tutorials recommend maximum redundancy immediately.

This project intentionally starts with a simpler design to allow us to demonstrate:

- NAT Gateway dependency
- Outbound connectivity failures
- Image pull failures
- Node bootstrap failures
- Recovery strategies

Future experiments will compare:

text Single NAT vs NAT Per AZ 

and evaluate the cost vs resiliency tradeoff.

---

# Karpenter Discovery Tags

Subnets are tagged for future Karpenter integration.

text karpenter.sh/discovery=autoscaling-chaos-dev 

These tags allow Karpenter to discover where it can provision capacity.

---

# Phase 3 – EKS Cluster Design

Planned.

Terraform plan completed successfully.

## Cluster

Name:

text autoscaling-chaos-dev 

Version:

text 1.32 

---

## Bootstrap Node Group

Configuration:

text Instance Type : t4g.large Desired       : 2 Minimum       : 2 Maximum       : 4 

Architecture:

text ARM64 

AMI:

text Amazon Linux 2023 

---

# Why Not Start With Karpenter?

A common mistake is trying to build:

text EKS + Karpenter 

with no worker nodes.

Karpenter itself runs as pods.

Pods require nodes.

This creates a bootstrap dependency problem:

text Karpenter needs nodes Nodes need Karpenter 

To solve this:

text Managed Node Group → Hosts Karpenter → Karpenter Creates Additional Nodes 

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

OIDC provider is being created.

This enables:

- AWS Load Balancer Controller
- Karpenter
- ExternalDNS
- OpenTelemetry

to access AWS APIs without storing credentials inside pods.

---

# Upcoming Phases

## Phase 4

Cluster Deployment

- Terraform Apply
- kubeconfig setup
- Node verification

---

## Phase 5

Core Platform Components

- Metrics Server
- AWS Load Balancer Controller
- Karpenter

---

## Phase 6

Autoscaling

- HPA
- KEDA
- Request-based scaling
- Connection-based scaling

---

## Phase 7

Spot Capacity Engineering

- Mixed instance types
- Spot interruption handling
- Capacity shortages
- Fallback strategies

---

## Phase 8

Chaos Engineering

- Node failures
- Spot interruptions
- NAT failures
- Subnet exhaustion
- ALB failures
- Elevated 5xx responses

---

## Phase 9

Large Event Simulation

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

## Phase 10

Global Platform Design

- Multi-region deployment
- Route53 latency routing
- CDN integration
- Regional failover

---

# Key Lesson

The biggest lesson of this project is expected to be:

Autoscaling is often not the difficult part.

The difficult part is finding capacity when everyone else is also trying to scale.

During major events:

- Spot inventory may be unavailable
- Specific instance families may be constrained
- Entire Availability Zones may be under pressure
- Network limits may be reached
- IP address exhaustion may occur

Designing for those realities is what separates a resilient platform from a platform that merely has an autoscaler configured.