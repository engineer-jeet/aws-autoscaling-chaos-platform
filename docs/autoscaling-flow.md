Autoscaling Flow

Overview

One of the primary objectives of this project was to understand how modern cloud-native platforms scale in response to changing demand.

Autoscaling in Kubernetes is often simplified as “increase replicas when CPU increases.” In reality, production autoscaling involves multiple independent systems working together across the application, orchestration, infrastructure, and cloud provider layers.

This document describes the complete scaling lifecycle implemented in this project using AWS Application Load Balancer, CloudWatch, KEDA, Horizontal Pod Autoscaler, and Karpenter.

⸻

Autoscaling Components

The platform uses the following components:

AWS Application Load Balancer

Receives incoming user traffic and distributes requests across application pods.

Amazon CloudWatch

Collects and stores Application Load Balancer metrics used to measure demand.

KEDA

Monitors CloudWatch metrics and converts them into Kubernetes scaling signals.

Horizontal Pod Autoscaler (HPA)

Adjusts application replica counts based on scaling recommendations.

Kubernetes Scheduler

Places pods onto available worker nodes.

Karpenter

Provisions and removes worker nodes based on scheduling demand.

⸻

End-to-End Scaling Lifecycle

The complete scaling workflow is shown below:

User Traffic
      |
      v
Application Load Balancer
      |
      v
CloudWatch Metrics
      |
      v
KEDA
      |
      v
Horizontal Pod Autoscaler
      |
      v
Deployment Replica Increase
      |
      v
New Pods Created
      |
      v
Kubernetes Scheduler
      |
      v
Karpenter (If Required)
      |
      v
EC2 Nodes Provisioned
      |
      v
Pods Scheduled
      |
      v
Traffic Served

Each component is responsible for a specific stage in the scaling process.

⸻

Why Request-Based Scaling Was Chosen

Many Kubernetes environments rely exclusively on CPU and memory metrics.

While these metrics are useful, they do not always represent actual user demand.

Consider the following example:

* Traffic suddenly doubles.
* Requests begin queuing.
* Latency starts increasing.
* CPU remains relatively low.

In this situation, CPU-based scaling reacts late because the infrastructure does not yet appear stressed.

Request volume, however, reflects user demand immediately.

For this reason, the platform was configured to scale using Application Load Balancer metrics collected through CloudWatch.

The primary metric used was:

RequestCountPerTarget

This allowed scaling decisions to be driven by incoming traffic rather than resource consumption alone.

⸻

Step 1 - Traffic Increase

The scaling process begins when incoming user traffic increases.

As request volume grows:

* More requests reach the Application Load Balancer.
* Target groups begin processing additional traffic.
* CloudWatch metrics begin increasing.

At this stage, the application is still operating with its existing replica count.

⸻

Step 2 - CloudWatch Metrics Increase

Application Load Balancer metrics are continuously published to CloudWatch.

As traffic increases:

RequestCountPerTarget

begins rising.

This metric becomes the primary indicator used to determine whether additional application capacity is required.

⸻

Step 3 - KEDA Polling

KEDA periodically polls CloudWatch.

During each polling cycle, KEDA evaluates whether the observed traffic exceeds the configured scaling threshold.

If the threshold is exceeded:

* KEDA generates a scaling recommendation.
* A Horizontal Pod Autoscaler is updated.
* Kubernetes receives a request to increase replica count.

At this stage, no pods have been created yet.

⸻

Step 4 - Horizontal Pod Autoscaler Increases Replicas

The Horizontal Pod Autoscaler adjusts the deployment replica count.

Example:

2 Pods
↓
4 Pods
↓
8 Pods

The exact number depends on:

* Current traffic
* Scaling thresholds
* Configured minimum replicas
* Configured maximum replicas

Kubernetes then begins creating additional pods.

⸻

Step 5 - Scheduler Attempts Placement

Once new pods are created, the Kubernetes Scheduler attempts to place them on available worker nodes.

Two outcomes are possible:

Sufficient Capacity Exists

If nodes have available CPU, memory, and networking resources:

Pods Created
↓
Pods Scheduled
↓
Pods Running

No infrastructure scaling is required.

Capacity Does Not Exist

If nodes cannot accommodate the new workloads:

Pods Created
↓
Pods Pending

At this point, infrastructure scaling becomes necessary.

⸻

Step 6 - Karpenter Detects Scheduling Pressure

Karpenter continuously monitors the cluster for unschedulable workloads.

When Pending pods are detected:

Pending Pods
↓
Karpenter Analysis
↓
Capacity Requirement Calculated
↓
EC2 Instance Launched

Karpenter selects the most appropriate instance type based on workload requirements and cluster configuration.

This process allows infrastructure capacity to grow dynamically as application demand increases.

⸻

Step 7 - Node Registration

After EC2 instances launch:

* The node joins the EKS cluster.
* Kubernetes registers the node.
* Available capacity increases.

The scheduler can now place previously Pending pods.

New Node Available
↓
Pods Scheduled
↓
Pods Running

Application capacity expands and traffic is distributed across the newly created replicas.

⸻

Step 8 - Traffic Stabilization

Once additional pods and nodes become available:

* Request latency decreases.
* Queue depth reduces.
* Application capacity increases.
* User traffic is absorbed successfully.

The platform reaches a new steady state.

⸻

Scale Down Workflow

The scaling process also operates in reverse.

As traffic decreases:

Traffic Decreases
↓
CloudWatch Metrics Decrease
↓
KEDA Detects Lower Demand
↓
HPA Reduces Replicas
↓
Pods Terminated
↓
Node Utilization Falls
↓
Karpenter Consolidates Nodes
↓
Infrastructure Cost Reduced

This allows the platform to optimize resource consumption during periods of low demand.

⸻

Potential Failure Points

The autoscaling workflow depends on multiple independent systems.

A failure in any stage can impact scaling behavior.

Examples include:

CloudWatch Metrics Not Updating

KEDA receives stale data and scaling decisions become inaccurate.

KEDA Polling Failures

Traffic increases but scaling recommendations are never generated.

HPA Misconfiguration

Metrics are available but replica counts do not increase as expected.

Scheduler Constraints

Pods remain Pending despite scaling requests.

Karpenter Provisioning Failures

Infrastructure cannot expand even though demand exists.

EC2 Launch Failures

AWS capacity constraints prevent new nodes from being created.

Networking Constraints

Pod scheduling may fail due to ENI limits, subnet exhaustion, or IP allocation failures.

⸻

Key Lessons Learned

Several important observations emerged from implementing and testing this architecture.

Autoscaling Is A Multi-System Workflow

Scaling is not performed by a single component.

It requires coordination between:

* CloudWatch
* KEDA
* HPA
* Scheduler
* Karpenter
* EC2

Application Scaling And Infrastructure Scaling Are Different Problems

Increasing pod count does not guarantee sufficient cluster capacity.

Infrastructure must also be able to expand when required.

User Demand Is More Important Than CPU

CPU utilization is only one indicator of system load.

Request rates often provide a more accurate representation of user demand.

Networking Can Become A Scaling Bottleneck

Even when CPU and memory are available, scaling may fail if networking resources such as ENIs, pod IPs, or subnet capacity become exhausted.

⸻

Conclusion

The autoscaling implementation in this project demonstrates how modern Kubernetes platforms can respond dynamically to changing demand.

By combining request-based metrics, Kubernetes-native autoscaling, and dynamic node provisioning, the platform is capable of scaling both application capacity and infrastructure capacity while maintaining operational efficiency.

More importantly, the implementation highlights that successful autoscaling requires understanding the interactions between multiple systems rather than focusing on any single component in isolation.