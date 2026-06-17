Capacity Planning

Overview

Capacity planning is the process of determining how much infrastructure, compute capacity, and application capacity is required to support expected traffic while maintaining acceptable performance, reliability, and availability.

A common misconception is that autoscaling eliminates the need for capacity planning. In reality, the two disciplines solve different problems.

Autoscaling answers:

“How do we add capacity?”

Capacity planning answers:

“How much capacity is required?”

Without proper planning, autoscaling systems may react too slowly, infrastructure limits may be exhausted, or workloads may become unavailable during failure scenarios.

This document summarizes the capacity planning exercises performed as part of the AWS EKS Autoscaling Platform project.

⸻

Objectives

The primary objectives of the capacity planning exercise were:

* Understand application throughput characteristics
* Estimate pod-level capacity
* Estimate node-level capacity
* Evaluate scaling behavior under load
* Calculate safe operating limits
* Model failure scenarios
* Establish realistic safety margins

The goal was not to identify the maximum possible throughput, but to understand how much traffic the platform could reliably support while maintaining operational headroom.

⸻

Test Environment

Infrastructure Components

* Amazon EKS
* AWS Application Load Balancer
* KEDA
* Horizontal Pod Autoscaler
* Karpenter
* CloudWatch
* NGINX Test Application

Cluster Configuration

Worker Nodes:

2 x t4g.large

Node Specifications:

2 vCPU
8 GB Memory

Cluster Capacity:

4 vCPU
16 GB Memory

This environment represents a small but realistic platform capable of demonstrating autoscaling, infrastructure provisioning, and load distribution behavior.

⸻

Load Testing Methodology

Load testing was performed using k6.

The objective was to generate sustained traffic against the Application Load Balancer and observe:

* Request throughput
* Latency
* Error rates
* Pod scaling behavior
* Node scaling behavior

The exercise was designed to validate autoscaling workflows rather than stress the application to failure.

⸻

Load Test Results

Traffic Statistics

Requests Processed: 607,788
Throughput:
~1125 Requests Per Second

Application Capacity

Pods:
4

Infrastructure Capacity

Nodes:
2

Performance Metrics

Average Latency:
69 ms
P95 Latency:
158 ms
Error Rate:
0.02%

Observations

The platform remained stable throughout testing.

Key observations included:

* Successful ALB metric generation
* CloudWatch metric collection
* KEDA scaling activity
* HPA replica management
* Karpenter node provisioning
* Low error rates under sustained traffic

No significant bottlenecks were observed during the test window.

⸻

Pod Capacity Analysis

Based on observed traffic:

1125 RPS
4 Pods

Estimated capacity per pod:

1125 / 4
≈ 281 Requests Per Second

This value should not be considered a hard limit.

Real-world application behavior changes over time due to:

* New features
* Additional dependencies
* Database interactions
* Increased payload sizes
* Logging overhead
* Runtime behavior

For planning purposes, a conservative operating target should be used.

Recommended planning capacity:

250 Requests Per Second Per Pod

This introduces operational headroom and reduces the likelihood of saturation during unexpected traffic spikes.

⸻

Node Capacity Analysis

Based on observed traffic:

1125 RPS
2 Nodes

Estimated capacity per node:

1125 / 2
≈ 562 Requests Per Second

Again, this should be treated as an approximation rather than a guaranteed limit.

Node capacity is influenced by multiple factors:

* CPU utilization
* Memory utilization
* Network throughput
* Pod density
* ENI limits
* Application characteristics
* Storage performance
* Dependency latency

Capacity planning should always account for these variables rather than relying solely on throughput calculations.

⸻

Autoscaling Strategy

The platform uses request-driven autoscaling rather than relying exclusively on CPU utilization.

Scaling workflow:

Traffic
    ↓
Application Load Balancer
    ↓
CloudWatch Metrics
    ↓
KEDA
    ↓
Horizontal Pod Autoscaler
    ↓
Additional Pods
    ↓
Karpenter
    ↓
Additional Nodes

This design allows scaling decisions to reflect actual user demand.

⸻

Scale-Out Workflow

As traffic increases:

Traffic Increase
        ↓
ALB Request Count Increases
        ↓
CloudWatch Metrics Increase
        ↓
KEDA Trigger Activates
        ↓
HPA Increases Replica Count
        ↓
Additional Pods Created
        ↓
Karpenter Adds Capacity If Required

Application capacity and infrastructure capacity grow together.

⸻

Scale-In Workflow

As traffic decreases:

Traffic Decreases
        ↓
CloudWatch Metrics Drop
        ↓
KEDA Detects Lower Demand
        ↓
HPA Reduces Replicas
        ↓
Pods Terminated
        ↓
Karpenter Consolidates Nodes

This reduces infrastructure costs while maintaining service availability.

⸻

Safety Margins

Production systems should never operate continuously at maximum observed capacity.

Unexpected events can rapidly consume available resources.

Examples include:

* Traffic spikes
* Deployment issues
* Dependency failures
* Spot interruptions
* Availability Zone failures

For this reason, capacity planning should include operational headroom.

Recommended headroom:

25% - 30%

Planning formula:

Required Capacity =
Expected Capacity × 1.3

This provides sufficient buffer for most operational scenarios.

⸻

Scenario Analysis: High Traffic Event

Consider an application expected to receive:

10,000 Requests Per Second

Assuming:

250 RPS Per Pod

Required pods:

10000 / 250
= 40 Pods

Adding 25% operational headroom:

40 × 1.25
= 50 Pods

Recommended deployment size:

50 Pods

This provides additional resilience against traffic spikes and infrastructure failures.

⸻

Availability Zone Failure Planning

Assume:

50 Pods

Distributed across:

AZ-A
AZ-B
AZ-C

Distribution:

17 Pods
17 Pods
16 Pods

If AZ-B becomes unavailable:

Remaining capacity:

17 + 16
= 33 Pods

The application remains available.

However:

* Remaining pods carry additional load
* Operational headroom decreases
* Additional scale-out may be required

This demonstrates why capacity planning must account for failure domains rather than assuming ideal operating conditions.

⸻

Spot Interruption Planning

Consider:

40 Spot Pods
10 On-Demand Pods

If AWS reclaims:

20 Spot Pods

Remaining capacity:

30 Pods

The application remains operational while replacement capacity is provisioned.

Recommended practices include:

* Mixed Spot and On-Demand capacity
* Baseline On-Demand nodes
* Interruption handling
* Node Termination Handler
* Karpenter interruption processing

Capacity planning should assume that interruptions will occur rather than treating them as rare events.

⸻

Capacity Planning Beyond Compute

One of the most important lessons from this project was that compute resources are only one part of capacity planning.

Additional limits include:

Networking

* ENI limits
* Pod IP availability
* Subnet capacity
* VPC CIDR allocation

Kubernetes

* Pod density
* Scheduler constraints
* Node provisioning delays

Infrastructure

* EC2 capacity availability
* Spot inventory
* Service quotas

A platform may run out of networking capacity long before CPU or memory resources are exhausted.

⸻

Key Lessons Learned

Autoscaling Does Not Replace Capacity Planning

Autoscaling determines how capacity is added.

Capacity planning determines how much capacity is required.

Both disciplines are necessary.

Scaling Speed Matters

Capacity is not useful if it cannot be provisioned quickly enough.

Provisioning delays must be included in planning assumptions.

Headroom Is A Reliability Feature

Unused capacity is not waste.

It is a buffer that protects systems during unexpected events.

Failure Planning Is Essential

Capacity should be planned for:

* Normal operation
* Peak traffic
* Availability Zone failures
* Spot interruptions
* Infrastructure degradation

CPU Utilization Alone Is Insufficient

Effective planning requires understanding:

* CPU
* Memory
* Pod Density
* ENI Limits
* Subnet Capacity
* Traffic Patterns
* Failure Domains

⸻

Future Enhancements

Potential future areas of exploration include:

* Multi-AZ node pools
* Multi-region deployment
* Predictive scaling
* Scheduled scaling
* Cost optimization analysis
* Load balancer sharding
* Concurrency-based scaling
* SLO-driven capacity planning

These topics represent natural extensions of the work completed in this project.

⸻

Conclusion

Capacity planning is fundamentally about understanding limits before they become problems.

While autoscaling technologies such as KEDA and Karpenter simplify the process of adding capacity, they do not eliminate the need to understand workload behavior, infrastructure constraints, and failure scenarios.

The exercises performed during this project demonstrate that effective capacity planning requires consideration of application demand, infrastructure limits, networking constraints, operational headroom, and system resilience.

A reliable platform is not one that scales indefinitely. It is one that has been designed with sufficient capacity, realistic assumptions, and appropriate safety margins to handle both expected growth and unexpected failures.