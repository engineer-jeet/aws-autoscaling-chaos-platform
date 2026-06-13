AWS Autoscaling & Chaos Engineering Platform

Staff Engineer Implementation Journal

Date: 11-Jun-2026

Objective

Continue development of the AWS Autoscaling Platform and progress from basic node provisioning into production-grade autoscaling patterns involving HPA, Karpenter, KEDA, resource scheduling, and capacity planning.

The primary goal was not simply to deploy Kubernetes components, but to understand how workload demand propagates through the platform stack:

Business Demand → Metrics → Pod Scaling → Scheduling → Node Scaling → Infrastructure Provisioning

⸻

Starting State

Cluster State:

* EKS Cluster: autoscaling-chaos-dev
* Region: ap-south-1
* Kubernetes: 1.32
* Bootstrap Capacity:
    * 2 x t4g.large nodes
* Karpenter installed and functional
* Previous day’s issue with NodeClaims not joining cluster had already been resolved via EKS Access Entries.

Existing Architecture:

Users
↓
Application
↓
Pods
↓
Scheduler
↓
Karpenter
↓
EC2

The missing piece was application autoscaling.

⸻

Phase 1 - Metrics Server Validation

Goal

Validate that HPA prerequisites existed before implementing workload autoscaling.

Validation:

kubectl top nodes

Result:

* Metrics Server healthy
* CPU and Memory metrics available
* HPA could consume metrics

Production Lesson:

HPA depends on metrics availability. If Metrics Server fails, autoscaling becomes blind.

⸻

Phase 2 - Horizontal Pod Autoscaler (HPA)

Goal

Implement Kubernetes-native pod autoscaling.

Deployment:

cpu-app

Characteristics:

* nginx image replaced with CPU intensive workload
* Continuous CPU consumption
* Explicit resource requests defined

Initial Configuration:

requests:
cpu: 100m

limits:
cpu: 200m

HPA Configuration:

Target CPU: 50%
Min Replicas: 1
Max Replicas: 20

⸻

Observed HPA Behaviour

Initial State:

1 Pod

Observed:

CPU 250%
↓
4 Pods
↓
5 Pods
↓
10 Pods
↓
20 Pods

HPA behaved exactly as expected.

Key Learning:

HPA scales based on observed metrics, not infrastructure capacity.

HPA assumes the cluster can satisfy demand.

Infrastructure scaling is not HPA’s responsibility.

⸻

Phase 3 - HPA + Karpenter Interaction

Goal

Validate complete autoscaling chain.

Observed Flow:

High CPU
↓
HPA
↓
More Pods
↓
Pending Pods
↓
Karpenter
↓
New EC2 Node
↓
Pods Scheduled

This represented the first fully automated scaling path in the platform.

No manual node creation occurred.

⸻

Phase 4 - Scale Down Validation

Deployment deleted manually:

kubectl delete deployment cpu-app

Observed:

Pods terminated
↓
Node became empty
↓
Karpenter consolidation triggered
↓
NodeClaim removed
↓
EC2 terminated

Result:

Cluster returned to bootstrap capacity.

Production Lesson:

Karpenter lifecycle includes both:

* Scale Out
* Scale In

Consolidation is equally important because cost savings occur during scale-in.

⸻

Phase 5 - Orphaned HPA Discovery

Unexpected Observation:

Deployment removed but HPA still existed.

State:

Deployment: Deleted
Pods: Deleted
HPA: Present

Root Cause:

Deployment and HPA are separate Kubernetes resources.

Deleting a deployment does not automatically delete HPA.

Resolution:

kubectl delete hpa cpu-app

Production Lesson:

Resource cleanup matters.

Common orphaned resources:

* ALBs
* Target Groups
* EBS Volumes
* HPAs
* Security Groups

Large cloud bills often originate from forgotten resources.

⸻

Phase 6 - KEDA Installation

Goal

Move beyond CPU-based autoscaling.

Installation:

Helm
↓
KEDA Operator
↓
Metrics API Server
↓
Admission Webhooks

Observation:

KEDA deployed successfully.

Warning Observed:

Kubernetes 1.32
KEDA officially tested on 1.33+

Decision:

Acceptable for lab environment.

Would require validation before production rollout.

Production Lesson:

“Works” and “Supported” are different concepts.

⸻

Phase 7 - Understanding KEDA Architecture

Misconception Investigated:

“KEDA replaces HPA”

Finding:

Incorrect.

Actual Architecture:

ScaledObject
↓
KEDA Operator
↓
HPA
↓
Deployment
↓
Pods

KEDA extends HPA.

KEDA’s primary function:

External Signal
↓
Metric Translation
↓
HPA

⸻

Phase 8 - ScaledObject Implementation

Created:

kind: ScaledObject

Target:

keda-cpu-app

Trigger:

CPU

Observation:

KEDA automatically created:

keda-hpa-keda-cpu-app

without manual intervention.

Key Learning:

ScaledObject is essentially an autoscaling policy definition.

KEDA generates and manages the HPA.

⸻

Phase 9 - Resource Requests vs Actual Usage

Most Valuable Learning Of The Day

Initial Deployment:

requests:
cpu: 100m

Actual CPU Usage:

~2000m

Node Metrics:

103% CPU utilization

Unexpected Observation:

Karpenter did NOT scale.

Investigation:

No Pending Pods.

Reason:

Kubernetes schedules using requests.

Not actual consumption.

Scheduler Calculation:

Node Capacity:
2000m

Pod Request:
100m

20 Pods:
2000m

Scheduler believed everything fit.

Production Lesson:

Under-requesting resources causes:

* CPU saturation
* latency
* instability

while autoscaling appears healthy.

This is one of the most common production issues.

⸻

Phase 10 - Scheduling Pressure Experiment

Objective:

Demonstrate Karpenter trigger conditions.

Modified:

requests:
cpu: 1000m

limits:
cpu: 1000m

Result:

Scheduler Calculation:

20 Pods
×
1 CPU

=
20 CPUs Required

Cluster Capacity:

~4 CPUs

Outcome:

Pods entered Pending state.

⸻

Phase 11 - Real Karpenter Scale-Out

Observed:

Pending Pods
↓
NodeClaims
↓
EC2 Launches

Provisioned:

* c6g.xlarge
* c6g.xlarge
* c6g.xlarge
* c6g.2xlarge

Final Cluster:

2 bootstrap nodes
+
4 Karpenter nodes

Total:

6 nodes

Production Lesson:

Karpenter does NOT scale on CPU.

Karpenter scales on:

Unschedulable Pods

This is one of the most important concepts validated so far.

⸻

Phase 12 - Pending Pod Investigation

Unexpected Observation:

Two Pods remained Pending.

Investigation:

kubectl describe pod

Finding:

0/6 nodes available:
6 Insufficient cpu

Additional observations:

* Node registration delays
* Unregistered node taints
* NodeNotReady states during provisioning

Important Finding:

Raw CPU ≠ Allocatable CPU

Allocatable capacity reduced by:

* kubelet
* aws-node
* kube-proxy
* daemonsets
* system reservations

Production Lesson:

Capacity planning cannot rely on raw vCPU counts.

⸻

Key Architecture Concepts Validated

1. HPA scales Pods.
2. HPA does not scale infrastructure.
3. Karpenter scales Nodes.
4. Karpenter reacts to Pending Pods.
5. KEDA manages HPA.
6. Kubernetes schedules using Requests.
7. Actual utilization and scheduling are different concerns.
8. Autoscaling does not replace capacity planning.
9. Bin-packing affects cloud cost.
10. Allocatable resources matter more than theoretical resources.

⸻

Production Relevance

Today’s work reproduced real production behaviours:

* Unschedulable workloads
* Node provisioning delays
* Incorrect resource requests
* Autoscaling limits
* Capacity planning challenges
* Infrastructure cost tradeoffs

This moved the project beyond “Kubernetes deployment” into actual platform engineering and SRE territory.

⸻

Next Session Plan

1. Cleanup KEDA CPU experiment.
2. Observe Karpenter consolidation.
3. Implement SQS-driven autoscaling.
4. Validate Event-Driven Scaling.
5. Implement Kafka-based autoscaling.
6. Explore Consumer Lag scaling.
7. Introduce Spot capacity.
8. Continue toward:
    * ALB
    * WAF
    * Route53
    * Multi-NAT
    * Multi-Region
    * Chaos Engineering
    * Disaster Recovery

End State:

A complete understanding of how business demand translates into infrastructure scaling across Kubernetes and AWS.