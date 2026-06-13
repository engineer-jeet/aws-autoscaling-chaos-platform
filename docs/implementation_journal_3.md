# AWS Autoscaling & Chaos Engineering Platform
## Engineering Journal
### Date: 12-Jun-2026

---

# Session Goal

Continue Autoscaling Platform implementation by:

1. Completing KEDA + SQS autoscaling
2. Implementing production-grade IAM authentication using IRSA
3. Understanding Karpenter Spot provisioning
4. Creating dedicated Spot NodePool
5. Observing full node lifecycle (creation → scheduling → deletion)
6. Learning production capacity planning concepts

---

# Starting State

Cluster healthy:

- EKS Cluster
- Karpenter Installed
- KEDA Installed
- 2 Bootstrap Nodes

Existing Nodes:

- ip-10-0-21-69
- ip-10-0-33-15

No active NodeClaims.

---

# Part 1 — KEDA + SQS Autoscaling

## Concept Review

### Why KEDA Exists

Traditional HPA scales from:

- CPU
- Memory

KEDA extends Kubernetes autoscaling using external event sources:

- SQS
- Kafka
- RabbitMQ
- Prometheus
- Datadog
- Azure Service Bus
- Redis
- etc.

---

## Key KEDA Objects

### ScaledObject

Purpose:

Connect workload to external metric source.

Example:

Deployment
↓
ScaledObject
↓
SQS Queue

---

### TriggerAuthentication

Purpose:

How KEDA authenticates to external systems.

In our implementation:

AWS IRSA

instead of:

- AWS Access Key
- AWS Secret Key

---

# Part 2 — Production Authentication (IRSA)

## Design Decision

Decision:

Do not use AWS keys.

Use production-grade IAM approach.

---

## OIDC Validation

Verified cluster OIDC provider:

https://oidc.eks.ap-south-1.amazonaws.com/id/A104D248592F0E30FE0B2D5161D25664

Confirmed IAM OIDC provider already exists.

---

## Created SQS Queue

Created:

orders-queue

Region:

ap-south-1

Queue ARN:

arn:aws:sqs:ap-south-1:974318644331:orders-queue

---

## IAM Policy

Created:

KedaSQSReaderPolicy

Permissions:

- sqs:GetQueueAttributes
- sqs:GetQueueUrl
- sqs:ReceiveMessage

Purpose:

Allow KEDA to read queue depth.

---

## IAM Trust Policy

Created:

keda-trust-policy.json

Purpose:

Allow ServiceAccount:

keda/keda-operator

to assume IAM role

using:

sts:AssumeRoleWithWebIdentity

---

## IAM Role

Created:

KedaSQSRole

Attached:

KedaSQSReaderPolicy

---

## IRSA Configuration

Annotated ServiceAccount:

keda-operator

with:

eks.amazonaws.com/role-arn

Verified:

- AWS_ROLE_ARN
- AWS_WEB_IDENTITY_TOKEN_FILE

inside KEDA Operator pod.

---

## KEDA Restart

Restarted KEDA Operator.

Verified successful startup.

Observed:

KEDA Version 2.20.1

Controllers healthy.

---

# Part 3 — KEDA SQS Scaling Test

## Created Worker Deployment

Deployment:

sqs-worker

Purpose:

Target workload for queue-based scaling.

---

## TriggerAuthentication

Created:

keda-aws-auth

Authentication Type:

aws

Using:

IRSA

---

## ScaledObject

Connected:

orders-queue

to:

sqs-worker

---

## Queue Length Discussion

Reviewed:

Queue Length

Meaning:

ApproximateNumberOfMessages

Example:

20 messages

means:

20 items waiting to be processed.

---

## HPA Creation

After applying ScaledObject:

Observed:

keda-hpa-sqs-worker-scaler

created automatically.

Important learning:

KEDA creates HPA.

KEDA itself does not directly scale pods.

Flow:

Queue
↓
KEDA
↓
HPA
↓
Pods

---

## Queue Injection Test

Sent:

20 SQS Messages

to queue.

Verified:

ApproximateNumberOfMessages = 20

---

## Scaling Event

Observed:

TARGETS

20/5

then:

5/5

and deployment scaled to:

4 replicas

Successfully demonstrated:

Queue Depth
↓
KEDA
↓
HPA
↓
Pod Scaling

---

# Part 4 — Spot Capacity Concepts

## Spot vs On-Demand

Discussion:

Critical workloads

vs

Elastic workloads

Examples:

### On-Demand

- Authentication
- Payments
- DRM
- Subscription Services

### Spot

- Analytics
- Telemetry
- Recommendation Engines
- Batch Processing

---

# Part 5 — Karpenter Deep Dive

## NodePool

User confusion clarified.

Definition:

Rules for node creation.

Examples:

- Spot
- On-Demand
- ARM64
- AMD64

---

## EC2NodeClass

Definition:

Blueprint for creating nodes.

Contains:

- AMI
- IAM Role
- Subnets
- Security Groups

---

## NodeClaim

Definition:

Actual request for a node.

Relationship:

NodePool
↓
NodeClaim
↓
EC2
↓
Node

---

# Part 6 — Spot NodePool Creation

Created:

spot NodePool

Requirements:

- capacity-type = spot
- arch = arm64

Label:

workload=spot

---

## Spot Workload

Created deployment:

spot-worker

Characteristics:

- 3 replicas
- 1 CPU request each

Node selector:

workload=spot

Purpose:

Force scheduling onto Spot nodes.

---

# Part 7 — First Failure

Observed:

Pods Pending

No NodeClaims visible.

Investigated:

kubectl describe pod

Found:

incompatible requirements

label "workload" does not have known values

Root Cause:

NodePool label configuration mismatch.

Corrected configuration.

---

# Part 8 — Second Failure

Karpenter created NodeClaim:

spot-4pr4x

Immediately failed.

Investigated:

kubectl logs deployment/karpenter

Discovered:

AuthFailure.ServiceLinkedRoleCreationNotPermitted

Root Cause:

Missing AWS Spot Service Linked Role.

---

## Production Troubleshooting Exercise

Flow:

Pending Pods
↓
Scheduler Events
↓
NodeClaim
↓
Karpenter Logs
↓
AWS Error
↓
IAM Root Cause

Very realistic platform engineering scenario.

---

# Part 9 — AWS Spot Service Role Fix

Created:

AWSServiceRoleForEC2Spot

Command:

aws iam create-service-linked-role \
--aws-service-name spot.amazonaws.com

---

# Part 10 — Successful Spot Provisioning

Immediately after role creation:

Observed:

NodeClaim Created

Example:

spot-q2cjg

---

## AWS Decision

AWS selected:

i8ge.xlarge

without us specifying instance type.

Important learning:

Karpenter chooses capacity.

AWS chooses instance type.

---

## Node Registration

New node joined:

ip-10-0-59-160

Cluster state:

- 2 Bootstrap Nodes
- 1 Spot Node

---

## Pod Scheduling

Observed:

Pending
↓
ContainerCreating
↓
Running

for all three Spot worker pods.

Successfully demonstrated:

Pending Pods
↓
NodePool Match
↓
NodeClaim
↓
Spot EC2
↓
Node Registration
↓
Pod Scheduling

---

# Part 11 — Node Lifecycle Understanding

## Key Realization

Pods do NOT create nodes.

Instead:

Pods Pending
↓
Scheduler cannot place
↓
Karpenter notices
↓
NodeClaim created
↓
Node launched

Trigger for Karpenter:

Pending Pods

NOT:

- Users
- Traffic
- Requests

---

# Part 12 — Scale Down Demonstration

Deleted:

spot-worker

Observed:

Node becomes empty
↓
Karpenter consolidation
↓
NodeClaim removed
↓
Spot EC2 terminated
↓
Node disappears

Final cluster state:

- ip-10-0-21-69
- ip-10-0-33-15

Only bootstrap nodes remain.

Successfully demonstrated full lifecycle:

Create Node
↓
Use Node
↓
Delete Node

---

# Capacity Planning Discussion

Extensive discussion on:

- IPL Final
- Game of Thrones Release
- Black Friday

Topics covered:

### Prewarming

- Warm Nodes
- Warm Pods
- Headroom

### Capacity Planning

Expected Load
+
Pre-Provisioned Capacity
+
Autoscaling

### Real Architecture

On-Demand
+
Spot
+
Karpenter
+
HPA/KEDA

### Important Learning

Autoscaling is:

Variance Handling

NOT:

Capacity Planning Replacement

---

# Key Takeaways

### 1

HPA/KEDA decides:

How many Pods?

### 2

Karpenter decides:

How many Nodes?

### 3

AWS decides:

Which Instance Type?

### 4

NodePool = Rules

### 5

EC2NodeClass = Blueprint

### 6

NodeClaim = Actual Node Request

### 7

Pending Pods trigger Karpenter

### 8

Prewarming reduces scaling latency

### 9

Spot failures must have fallback strategy

### 10

Production troubleshooting is often IAM-related

---

# End State

Cluster:

- Healthy
- KEDA Installed
- IRSA Configured
- Karpenter Operational

Nodes:

- 2 Bootstrap Nodes
- 0 Spot Nodes

Validated Successfully:

- KEDA
- IRSA
- SQS Autoscaling
- Karpenter Spot Provisioning
- Node Lifecycle Management
- Spot Provisioning Troubleshooting
- Production Capacity Planning Concepts

---

# Next Session Plan

1. Capacity Planning Exercise
2. Prewarming Strategy Lab
3. Traffic Surge Simulation
4. HPA + Karpenter Combined Scaling
5. ALB Deployment
6. 503 Error Investigation
7. Latency Analysis
8. Spot Failure Scenarios
9. On-Demand Fallback Patterns
10. SRE Incident Response Exercises

---

# Session Outcome

Major milestone achieved:

KEDA
+
IRSA
+
SQS Autoscaling
+
Karpenter Spot Provisioning
+
Node Lifecycle Management

with real-world production troubleshooting and operational understanding.

This session moved beyond Kubernetes concepts and into practical platform engineering, capacity planning, autoscaling architecture, Spot lifecycle management, and production-style incident debugging.