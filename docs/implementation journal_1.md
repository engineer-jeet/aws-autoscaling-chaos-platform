# Staff Engineer Implementation Journal

## Project
AWS Autoscaling & Chaos Engineering Platform

## Date
11-Jun-2026

## Engineer
Bishwajeet Dey

## Phase
Phase 2 - Karpenter Implementation & Validation

---

# Executive Summary

Today's objective was to move the platform from static infrastructure to dynamic infrastructure.

Prior to this session, the EKS cluster consisted solely of a Managed Node Group with fixed capacity. Any workload exceeding the available cluster resources would result in unschedulable pods and eventual application degradation.

The goal of this implementation was to introduce Karpenter and validate the complete node lifecycle:

text Unschedulable Pod         ↓ Karpenter Detection         ↓ NodeClaim Creation         ↓ EC2 Launch         ↓ Node Registration         ↓ Pod Scheduling         ↓ Workload Removal         ↓ Node Consolidation         ↓ EC2 Termination 

The session successfully validated both scale-out and scale-in behavior.

The most significant learning was troubleshooting a node registration failure caused by missing EKS Access Entries, despite successful EC2 provisioning.

---

# Architecture Before Implementation

Existing environment:

text AWS Region └── ap-south-1  EKS Cluster └── autoscaling-chaos-dev  Managed Node Group ├── t4g.large └── t4g.large  Workloads └── Scheduled only on bootstrap capacity 

Characteristics:

- Fixed capacity
- No node autoscaling
- No dynamic EC2 provisioning
- Cluster capacity tied directly to Managed Node Group size

Failure mode:

text More Pods       ↓ Insufficient Capacity       ↓ Pending Pods       ↓ Application Impact 

---

# Implementation Approach

## What was managed by Terraform

Infrastructure components already provisioned through Terraform:

### Networking

- VPC
- Public Subnets
- Private Subnets
- Route Tables
- NAT Gateway
- Internet Gateway

### EKS

- EKS Control Plane
- Managed Node Group
- OIDC Provider
- IAM Roles
- Security Groups

### State Management

- S3 Remote State
- DynamoDB Lock Table

Reason:

These are long-lived platform resources and must remain reproducible, version controlled and recoverable.

---

## What was intentionally performed manually

Today's Karpenter validation activities were executed manually.

Examples:

bash kubectl apply kubectl describe kubectl logs kubectl get aws eks list-access-entries 

Reason:

At this stage we were validating behavior rather than deploying production-ready automation.

Manual execution allows rapid troubleshooting and architectural understanding before codifying the solution.

Production expectation:

Eventually:

text Terraform     ↓ Karpenter     ↓ NodeClass     ↓ NodePool 

should all become Infrastructure as Code.

---

# EC2NodeClass Implementation

Created:

text EC2NodeClass default 

Purpose:

Provide AWS-specific configuration required to launch nodes.

Configuration included:

- Amazon Linux 2023
- ARM64-compatible AMIs
- Security Group discovery
- Subnet discovery
- Node IAM role

Important realization:

EC2NodeClass does not provision capacity.

It merely defines:

text How nodes should be built 

Equivalent concept:

text Launch Template 

for Karpenter.

---

# NodePool Implementation

Created:

text NodePool default 

Configuration:

yaml Architecture: arm64  Capacity: on-demand  CPU Limit: 100  Consolidation: enabled  Expiration: 720h 

Purpose:

Provide provisioning rules.

Important distinction learned:

text EC2NodeClass = Infrastructure Template  NodePool = Provisioning Policy 

NodePool answers:

text When should nodes be created? What nodes are allowed? 

---

# Validation Strategy

A workload was required that would intentionally exceed available cluster capacity.

Created:

text inflate deployment 

Purpose:

Generate unschedulable pods.

This simulates:

text Traffic Increase 

without requiring actual users.

Expected outcome:

text Pods Pending         ↓ Karpenter reacts 

---

# First Test Results

Observed:

text 6 Pods Requested  2 Running 4 Pending 

This confirmed:

- Scheduler functioning correctly
- Existing capacity exhausted

Karpenter should now provision capacity.

---

# Karpenter Event Sequence

Observed in logs:

text found provisionable pod(s) 

followed by:

text computed new nodeclaim(s) 

followed by:

text created nodeclaim 

followed by:

text launched nodeclaim 

Instance selected:

text c6g.2xlarge 

This validated:

- NodePool evaluation
- Instance type selection
- EC2 API interaction

At this point the team expected pods to become Running.

They did not.

---

# Incident #1

## Symptom

Pods remained Pending.

Despite:

text EC2 Instance = Running 

Workload state remained:

text Pending 

---

# Investigation Timeline

## Observation 1

NodeClaim existed.

Command:

bash kubectl get nodeclaim 

Result:

text READY = Unknown 

---

## Observation 2

Detailed inspection:

bash kubectl describe nodeclaim 

Revealed:

text Launched = True  Registered = Unknown  Ready = Unknown 

Critical insight:

AWS successfully launched infrastructure.

Failure occurred after launch.

---

# Hypotheses Considered

### Hypothesis 1

Node never launched.

Rejected.

Evidence:

text EC2 Instance ID present 

---

### Hypothesis 2

Node launch failed.

Rejected.

Evidence:

text Launched = True 

---

### Hypothesis 3

Networking issue.

Possible but unproven.

Insufficient evidence.

---

### Hypothesis 4

IAM or Authentication issue.

Most likely.

Further investigation required.

---

# Investigation of Controller Logs

Observed:

text ec2:DescribeInstanceStatus UnauthorizedOperation 

and

text iam:ListInstanceProfiles AccessDenied 

Initial conclusion:

Karpenter IAM permissions incomplete.

---

# Fix #1

Expanded Karpenter Controller permissions.

Added missing permissions.

Result:

Some controller errors reduced.

However:

text Node still not registered 

Conclusion:

This was not the primary root cause.

---

# Root Cause Discovery

Investigation shifted toward EKS authentication.

Executed:

bash aws eks list-access-entries 

Result:

Existing entries:

text AWSServiceRoleForAmazonEKS  Bootstrap Node Group Role  coreSre User 

Missing:

text autoscaling-chaos-dev-karpenter-node 

This was the breakthrough moment.

---

# Root Cause

Karpenter had permission to launch EC2 instances.

EKS did not trust those instances.

Effectively:

text EC2 Node        ↓ Attempts to join cluster        ↓ Authentication denied 

Result:

text Registered = Unknown 

forever.

---

# Fix #2

Added access entry for:

text autoscaling-chaos-dev-karpenter-node 

Validation:

bash aws eks list-access-entries 

Confirmed role presence.

No further infrastructure modifications required.

---

# Recovery

Within minutes:

NodeClaim status transitioned:

text Registered = True  Ready = True 

Node appeared:

text ip-10-0-16-47 

inside cluster.

This conclusively validated root cause analysis.

---

# Successful Scale-Out

Immediately after registration:

Pods transitioned:

text Pending        ↓ ContainerCreating        ↓ Running 

Final placement:

text Bootstrap Node 1 └── 1 Pod  Bootstrap Node 2 └── 1 Pod  Karpenter Node ├── 4 Pods 

Validation successful.

---

# Successful Scale-In

Workload removed.

Observed:

text No resources found 

Expected Karpenter behavior:

text Empty Node       ↓ Consolidation       ↓ Termination 

Actual result:

Node disappeared.

NodeClaim disappeared.

Cluster returned to:

text 2 Nodes 

only.

Scale-in validated.

---

# Production Learnings

The biggest misconception corrected today:

Many engineers believe:

text Karpenter = Node Autoscaling 

Reality:

text Users     ↓ HPA/KEDA     ↓ Pods     ↓ Karpenter     ↓ Nodes 

Today validated only:

text Pods     ↓ Nodes 

Tomorrow begins:

text Metrics     ↓ Pods 

using HPA.

---

# Risks Identified

Current NodePool is intentionally broad.

Allowed instance families include:

text c6g c7g c8g  m6g m7g m8g  r6g r7g r8g 

Production recommendation:

Constrain instance selection for:

- Predictable cost
- Predictable performance
- Easier capacity planning

---

# Technical Debt

1. Karpenter resources not yet managed through Terraform.
2. Access Entry management should move into Terraform.
3. Controller IAM policy requires cleanup and least-privilege review.
4. Spot capacity strategy not yet implemented.
5. HPA not yet integrated.

---

# Session Outcome

Status:

text SUCCESS 

Validated:

✓ NodeClass

✓ NodePool

✓ NodeClaim

✓ EC2 Launch

✓ Node Registration

✓ Pod Scheduling

✓ Scale-Out

✓ Scale-In

✓ Root Cause Analysis

✓ IAM Troubleshooting

✓ EKS Access Entry Troubleshooting

This marks the first fully operational autoscaling capability within the AWS Autoscaling & Chaos Engineering Platform.

Next milestone:

Horizontal Pod Autoscaler (HPA)

CPU
 ↓
Pods
 ↓
Karpenter
 ↓
Nodes