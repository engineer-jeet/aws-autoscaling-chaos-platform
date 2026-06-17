# Spot Interruption Handling

## Overview

Amazon EC2 Spot Instances provide access to unused AWS capacity at a significantly reduced cost compared to On-Demand instances.

Cost savings typically range from:

- 50%
- 70%
- 90%

depending on instance type and region.

The tradeoff is that AWS can reclaim Spot capacity at any time.

This makes Spot ideal for:

- Kubernetes workloads
- Stateless applications
- Batch jobs
- Worker nodes
- CI/CD runners

but requires interruption handling to prevent outages.

---

## Why This Matters

Spot instances are one of the most effective ways to reduce infrastructure costs in Kubernetes environments.

However, the operational challenge is that Spot capacity is inherently temporary. Nodes can disappear with little notice, which means applications must be designed to tolerate infrastructure loss.

For this reason, interruption handling is not an optional optimization. It is a core reliability requirement for any production platform using Spot capacity.

A well-designed Kubernetes platform should treat Spot interruptions as expected operational events rather than exceptional failures.

-----
# Why AWS Reclaims Spot Instances

AWS may reclaim Spot instances when:

- AWS requires the capacity
- Spot inventory becomes unavailable
- AWS needs the hardware for On-Demand customers

The exact reason is not exposed to customers.

The only guarantee is:

AWS sends a warning before termination.

---

# The 2-Minute Interruption Notice

Before terminating a Spot instance, AWS sends:

EC2 Spot Instance Interruption Warning

Approximately:

2 minutes before shutdown.

Example:

AWS
→ Spot Instance
→ Termination Notice

Time Remaining:

120 Seconds

Without interruption handling:

Node disappears immediately after termination.

Pods are lost.

Traffic may fail.

---

# Why This Is Dangerous In Kubernetes

Consider:

Node-1 (Spot)
├── Pod-A
├── Pod-B
└── Pod-C

AWS terminates Node-1.

Without preparation:

Node-1 disappears.

Pods disappear.

Connections are dropped.

Users may receive:

- 503
- Connection resets
- Increased latency

The scheduler only reacts after the failure occurs.

---

## Production Impact

Without interruption handling, Spot termination events can create several user-facing symptoms:

- Increased latency
- HTTP 503 responses
- Connection resets
- Reduced application capacity
- Failed background jobs
- Pod restarts
- Temporary service degradation

The severity depends on:

- Application replica count
- Pod distribution
- PodDisruptionBudget configuration
- Available replacement capacity
- Time required to launch new nodes

The goal of interruption handling is to reduce or eliminate these symptoms before the underlying node is terminated.

----

# Production Goal

We want Kubernetes to react BEFORE the node disappears.

Desired flow:

AWS
→ Interruption Notice
→ Drain Node
→ Move Pods
→ Launch Replacement Node
→ Terminate Original Node

Users should experience little or no disruption.

---

# Spot Interruption Event Flow

AWS
→ EventBridge
→ SQS Queue
→ Karpenter
→ Kubernetes

This allows Karpenter to respond before AWS terminates the node.

---

# EventBridge

EventBridge receives interruption notifications from AWS.

Example Events:

- Spot Interruption Warning
- Instance Rebalance Recommendation
- Scheduled Maintenance
- Instance State Changes

EventBridge acts as the event router.

---

# SQS Queue

EventBridge forwards events into an SQS queue.

Why?

Because Karpenter continuously polls SQS.

Benefits:

- Durable storage
- Reliable delivery
- Retry support
- Decoupled architecture

Flow:

AWS Event
→ EventBridge
→ SQS

---

# Karpenter Interruption Handling

Karpenter monitors the interruption queue.

When an interruption event arrives:

Karpenter:

1. Identifies affected node
2. Cordon node
3. Drain node
4. Provision replacement capacity
5. Allow AWS termination

---

# Node Cordoning

Cordoning means:

No new pods may be scheduled.

Command:

kubectl cordon <node>

Node remains active.

Existing pods continue running.

New pods cannot be placed there.

Purpose:

Prevent additional workload placement on a dying node.

---

# Node Draining

Draining means:

Move existing pods elsewhere.

Command:

kubectl drain <node>

Actions:

- Evict workloads
- Respect PodDisruptionBudgets
- Preserve availability

After draining:

Node becomes empty.

---

# Pod Eviction

Eviction is a controlled pod removal.

This is different from:

kubectl delete pod

Eviction allows Kubernetes to:

- Reschedule workload
- Respect disruption policies
- Maintain service availability

---

# PodDisruptionBudget (PDB)

Purpose:

Prevent too many pods from disappearing simultaneously.

Example:

Application Replicas:

4

PDB:

minAvailable: 2

Result:

At least two replicas must remain available during maintenance.

This protects against:

- Node failures
- Draining
- Spot interruptions
- Cluster upgrades

---

# Mixed Spot and On-Demand Strategy

Never run critical production workloads entirely on Spot.

Recommended:

70% Spot
30% On-Demand

or

80% Spot
20% On-Demand

Benefits:

- Significant cost savings
- Baseline guaranteed capacity
- Improved resiliency

Example:

10 Nodes

8 Spot
2 On-Demand

If Spot capacity disappears:

Critical workloads remain available.

---

## Workloads Suitable For Spot Capacity

Spot instances are most effective for workloads that can tolerate node replacement.

Good candidates include:

- Stateless web applications
- API services
- Background workers
- Batch processing jobs
- Event-driven workloads
- CI/CD runners
- Data processing pipelines

Less suitable candidates include:

- Single-instance applications
- Stateful databases
- Legacy applications with long startup times
- Workloads that cannot tolerate disruption

The more resilient the workload design, the more aggressively Spot capacity can be utilized.

-----

# Karpenter vs Node Termination Handler

## Traditional Approach

AWS
→ EventBridge
→ SQS
→ Node Termination Handler
→ Drain Node

---

## Modern Karpenter Approach

AWS
→ EventBridge
→ SQS
→ Karpenter
→ Drain Node

Benefits:

- Fewer components
- Simpler architecture
- Native integration

---

## Failure Scenario Example

Consider the following deployment:

Cluster Capacity

- 8 Spot Nodes
- 2 On-Demand Nodes

Application

- 20 Replicas
- PodDisruptionBudget: minAvailable=15

AWS reclaims three Spot nodes simultaneously.

Without interruption handling:

- Nodes disappear
- Pods terminate abruptly
- User traffic experiences errors

With interruption handling:

- Nodes are cordoned
- Pods are drained gracefully
- Karpenter launches replacement capacity
- Application availability is maintained

This illustrates why interruption handling is fundamentally a reliability feature rather than a cost optimization feature.

-----

# Production Recommendations

1. Always configure interruption handling.

2. Use mixed Spot and On-Demand capacity.

3. Implement PodDisruptionBudgets.

4. Enable Karpenter interruption queues.

5. Test interruption scenarios regularly.

6. Design workloads to tolerate node loss.

7. Never assume Spot capacity is permanent.

---

## Operational Lessons

Several important operational observations emerged during this analysis.

### Spot Capacity Is Not Unreliable

Spot capacity is often perceived as unreliable infrastructure.

In reality, Spot capacity becomes highly reliable when workloads are designed for interruption tolerance.

### Kubernetes Availability Depends On Redundancy

The objective is not to prevent node failures.

The objective is to ensure workloads remain available despite node failures.

### Replacement Speed Matters

Node replacement speed directly affects application availability.

Fast node provisioning combined with healthy replica distribution significantly reduces user impact.

### Cost Optimization Must Not Reduce Reliability

Cost savings should never come at the expense of availability.

A balanced Spot and On-Demand strategy provides both economic and operational benefits.

-------

# Interview Questions

Q:
What happens when AWS reclaims a Spot instance?

A:

AWS sends a two-minute interruption notice.

Karpenter receives the event via EventBridge and SQS.

The node is cordoned and drained.

Replacement capacity is provisioned.

Pods are rescheduled before termination.

---

Q:
Why use Spot instances in production?

A:

They provide significant cost savings while maintaining availability when combined with interruption handling, PodDisruptionBudgets, and baseline On-Demand capacity.

---

Q:
Why is a PodDisruptionBudget important?

A:

It prevents excessive pod eviction during node maintenance, upgrades, or Spot interruptions and helps maintain application availability.

---

Q:
What is the difference between cordon and drain?

A:

Cordon:
Stops new pods from being scheduled.

Drain:
Evicts existing pods and prepares the node for removal.



# Conclusion

Spot instances provide one of the highest-return cost optimization opportunities available in AWS.

However, successful adoption requires more than simply enabling Spot capacity.

Production environments must incorporate:

- Interruption handling
- PodDisruptionBudgets
- Redundant application replicas
- Replacement node provisioning
- Mixed capacity strategies

When these mechanisms are implemented correctly, Spot instances can significantly reduce infrastructure costs while maintaining high levels of application availability and operational resilience.

The most important lesson is that node loss should be treated as a normal operational event rather than an outage scenario. Kubernetes platforms that are designed with this assumption can safely leverage Spot capacity at scale.