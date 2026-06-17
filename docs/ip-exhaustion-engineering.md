# IP Exhaustion Engineering in Amazon EKS

Executive Summary

IP exhaustion is one of the most overlooked scaling constraints in Amazon EKS.

Unlike traditional infrastructure bottlenecks such as CPU or memory exhaustion, IP exhaustion can prevent applications from scaling even when compute resources remain available.

Because the AWS VPC CNI assigns real VPC IP addresses to Kubernetes pods, networking resources become a first-class capacity concern. As clusters grow, limitations related to ENIs, pod density, subnet capacity, and VPC address space can become the primary scaling bottleneck.

This document explains how IP allocation works in Amazon EKS, how exhaustion occurs at different layers of the network stack, how Prefix Delegation improves allocation efficiency, and how engineers can identify and resolve IP-related scaling failures in production environments.

---

# Overview

One of the most misunderstood scaling bottlenecks in Kubernetes is IP exhaustion.

Most engineers think Kubernetes scaling is limited by:

- CPU
- Memory
- Storage

However, in Amazon EKS there is another critical resource:

IP Addresses

A cluster may have:

- Healthy nodes
- Available CPU
- Available memory
- Working Karpenter
- Working KEDA

and still fail to schedule pods because no IP addresses are available.

This is one of the most common large-scale EKS networking problems and is frequently encountered in high-growth production environments.

---

Production Impact

IP exhaustion is particularly dangerous because it often appears as a Kubernetes scheduling problem rather than a networking problem.

A typical incident may present with symptoms such as:

* Pods stuck in Pending state
* KEDA creating additional replicas
* Karpenter attempting node provisioning
* Healthy CPU utilization
* Healthy memory utilization

At first glance, autoscaling appears to be malfunctioning.

However, the underlying issue may be that Kubernetes cannot obtain additional pod IP addresses from the AWS VPC CNI.

Without sufficient networking capacity:

* New pods cannot start
* New nodes may fail to launch
* Scaling events become ineffective
* Application availability may degrade during traffic spikes

For this reason, networking capacity should be considered a critical component of platform capacity planning rather than an implementation detail.

---


# Why IP Exhaustion Happens In EKS

Unlike many Kubernetes platforms, Amazon EKS uses the AWS VPC CNI plugin.

With AWS VPC CNI:

Every Pod receives a real VPC IP address.

Example:

Node:
10.0.16.100

Pods:
10.0.16.101
10.0.16.102
10.0.16.103
10.0.16.104

These are actual VPC IP addresses, not overlay network addresses.

Therefore:

Every Pod consumes one IP from the VPC subnet.

This creates a hard scaling dependency on:

- Subnet Capacity
- ENI Capacity
- Available Pod IPs

---

# How Pod Networking Works

Pod Creation Flow:

Pod Created
↓
Scheduler Places Pod
↓
AWS VPC CNI Requests IP
↓
IP Assigned To Pod
↓
Pod Starts

If an IP cannot be allocated:

Pod
↓
Pending

---

# AWS Networking Building Blocks

To understand IP exhaustion, we must understand:

VPC
↓
Subnet
↓
ENI
↓
IP Address
↓
Pod

---

# What Is An ENI?

ENI = Elastic Network Interface

Think of an ENI as:

Virtual Network Card

Example:

EC2 Instance
↓
ENI Attached
↓
IPs Assigned To ENI
↓
Pods Consume Those IPs

Each EC2 instance has limits on:

- Number of ENIs
- Number of IPs per ENI

These limits directly affect maximum pod density.

---

# Our Environment

Cluster:

Amazon EKS

Node Type:

t4g.large

Observed:

kubectl describe node

Result:

pods: 35

Therefore:

Maximum Pod Capacity Per Node = 35

Current Nodes = 2

Total Cluster Pod Capacity:

35 × 2

= 70 Pods

---

# Important Realization

Node Capacity Is Not Just CPU And Memory

Most Engineers Think:

Node Capacity =
CPU + Memory

In EKS:

Node Capacity =
CPU
Memory
ENI Limits
Available Pod IPs
Subnet Capacity

The smallest limit wins.

---

# Real Production Example

Suppose:

Node Capacity:
35 Pods

Current:
34 Pods Running

Traffic Spike Occurs

KEDA Creates:
10 More Pods

Scheduler Can Place:
1 Pod

Remaining:
9 Pods Pending

CPU may still be available.

Memory may still be available.

Pods remain Pending because the node has exhausted its networking capacity.

---

# The Three Levels Of IP Exhaustion

Level 1:
Node ENI/IP Exhaustion

Level 2:
Subnet Exhaustion

Level 3:
VPC CIDR Exhaustion

---

# Level 1 - Node ENI/IP Exhaustion

Most Common

Symptoms:

- Pods Pending
- Node Still Healthy
- CPU Available
- Memory Available

Cause:

Node reached maximum supported pod count.

Example:

t4g.large

35 Pod Limit

Current:

35 Pods Running

New Pod Arrives

Result:

Cannot Schedule

Solution:

Launch Additional Nodes

This is typically handled by:

Karpenter

or

Cluster Autoscaler

---

# Level 2 - Subnet Exhaustion

More Serious

Example:

Private Subnet

10.0.1.0/24

Total Addresses:

256

AWS Reserved:

5

Usable:

251

After Growth:

Pods:
200

Nodes:
20

Load Balancers:
10

Other Resources:
20

Available IPs:

0

Now:

Karpenter Attempts New Node
↓
AWS Cannot Allocate Node IP
↓
EC2 Launch Fails
↓
Pods Remain Pending

Even though:

CPU Available

Memory Available

This is a common production outage pattern.

---

# Level 3 - VPC CIDR Exhaustion

Rare

Example:

VPC

10.0.0.0/16

All available address space allocated.

No room remains for:

- New Subnets
- New Nodes
- New Services

Solution:

Associate Secondary CIDR Block

Example:

Primary:
10.0.0.0/16

Secondary:
100.64.0.0/16

New subnets are then created from the secondary CIDR.

---

# Current Project Network Design

VPC:

10.0.0.0/16

Private Subnets:

10.0.16.0/20
10.0.32.0/20
10.0.48.0/20

Each /20:

4096 Addresses

AWS Reserved:

5

Usable:

4091

Total Private Capacity:

4091 × 3

≈ 12,273 IPs

Conclusion:

This environment is nowhere near subnet exhaustion.

The more realistic bottleneck is:

Node Pod Density

not

Subnet Capacity

---

# Prefix Delegation

One of the most important EKS networking features.

Observed:

ENABLE_PREFIX_DELEGATION=false

Current cluster uses traditional IP allocation.

---

# Traditional Secondary IP Allocation

Without Prefix Delegation:

Node
↓
ENI
↓
Individual Secondary IPs
↓
Pods

Example:

AWS Allocates:

10.0.16.101
10.0.16.102
10.0.16.103

one-by-one.

Every new pod may require additional AWS IP allocation work.

Drawbacks:

- More AWS API calls
- Slower scaling
- Lower pod density
- Increased startup latency

---

# What Is Prefix Delegation?

Instead of allocating individual IPs:

AWS Allocates A Prefix

Example:

10.0.16.0/28

A /28 contains:

16 Addresses

Node Receives:

10.0.16.0
through
10.0.16.15

all at once.

Pods consume addresses locally.

No immediate AWS allocation request is required.

---

# Why Prefix Delegation Is Faster

Without Prefix Delegation:

Create Pod
↓
Request New IP
↓
AWS API Call

With Prefix Delegation:

Create Pod
↓
Take IP From Local Prefix Pool

No AWS API call.

Benefits:

- Faster Pod Startup
- Faster Scaling
- Reduced API Calls
- Higher Pod Density

---

# Critical Misconception

Prefix Delegation DOES NOT Create More IPs

Example:

Subnet:

10.0.16.0/20

Capacity:

4091 Usable IPs

After Prefix Delegation:

Capacity remains:

4091 Usable IPs

Prefix Delegation changes:

How IPs Are Allocated

NOT

How Many IPs Exist

---

# The Shopping Analogy

Without Prefix Delegation:

Node goes shopping
for every single IP.

Pod 1:
Buy 1 IP

Pod 2:
Buy 1 IP

Pod 3:
Buy 1 IP

With Prefix Delegation:

Node buys a box
containing 16 IPs.

Pods simply consume from the box.

Much faster.

---

# How To Enable Prefix Delegation

AWS VPC CNI Configuration:

aws-node DaemonSet

Environment Variable:

ENABLE_PREFIX_DELEGATION=true

Typically managed through:

Helm

or

Terraform Helm Release

Example:

env:
  ENABLE_PREFIX_DELEGATION=true

Production Recommendation:

1. Enable Prefix Delegation
2. Launch New Nodes
3. Drain Old Nodes
4. Remove Old Nodes

This ensures all nodes use the same networking model.

---

# Subnet Expansion Strategy

If Subnets Become Exhausted

Example:

Current:

10.0.16.0/20
10.0.32.0/20
10.0.48.0/20

Add:

10.0.64.0/20
10.0.80.0/20
10.0.96.0/20

No cluster rebuild required.

No downtime required.

Tag New Subnets:

karpenter.sh/discovery=autoscaling-chaos-dev

Karpenter automatically discovers them.

---

# Secondary CIDR Expansion Strategy

If VPC Address Space Is Exhausted

Current:

10.0.0.0/16

Attach:

100.64.0.0/16

Create New Subnets:

100.64.1.0/22
100.64.5.0/22
100.64.9.0/22

Tag them appropriately.

Karpenter begins using them automatically.

---

# Why Karpenter Makes This Easy

Current EC2NodeClass:

subnetSelectorTerms:
  - tags:
      karpenter.sh/discovery: autoscaling-chaos-dev

Karpenter discovers subnets by tags.

Not by hardcoded subnet IDs.

Benefits:

- Easy subnet expansion
- Easy CIDR expansion
- No NodePool changes
- No EC2NodeClass changes

Add Subnet
↓
Tag Subnet
↓
Karpenter Uses It

---

# Monitoring Recommendations

Monitor:

AvailableIpAddressCount

Subnet Utilization %

Pod Density

Node Density

Pending Pods

FailedCreatePodSandbox Events

Karpenter Node Launch Failures

Recommended Alerts:

Warning:
30% Free IPs Remaining

Critical:
10% Free IPs Remaining

---

# Common Interview Question

Question:

Pods are Pending.
CPU and Memory look healthy.
What would you investigate?

Answer:

1. Scheduler Events
2. Node Capacity
3. Pod Limits
4. ENI Limits
5. Available Pod IPs
6. Subnet Capacity
7. AWS VPC CNI Health
8. Prefix Delegation Status
9. Karpenter Logs

In EKS, pod scheduling failures are often caused by networking constraints rather than CPU or memory shortages.

---

# Key Takeaways

1. Every Pod In EKS Consumes A Real VPC IP Address.

2. Node Capacity Is Limited By:
   - CPU
   - Memory
   - ENI Limits
   - Available Pod IPs

3. Prefix Delegation Improves IP Allocation Efficiency But Does Not Create Additional IP Space.

4. Subnet Exhaustion Can Prevent New Nodes From Launching Even When CPU And Memory Are Available.

5. VPC CIDR Exhaustion Prevents Further Subnet Growth.

6. Karpenter's Tag-Based Discovery Makes Subnet Expansion Straightforward.

7. Large EKS Clusters Must Monitor Networking Capacity Just As Closely As CPU And Memory Capacity.

8. Successful Capacity Planning Includes:
   - CPU
   - Memory
   - Pod Density
   - ENI Limits
   - Subnet Capacity
   - VPC Capacity



How would you diagnose subnet IP exhaustion in EKS?

I would start with pod events and Pending pods, then inspect AWS VPC CNI (aws-node) logs for IP allocation failures.

Next, I would verify subnet capacity using AvailableIpAddressCount from the EC2 API. If Karpenter is involved, I would also review Karpenter logs and NodeClaims for node launch failures caused by exhausted subnet address space.



---

# How To Detect IP Exhaustion In Production

One of the most important operational skills for an SRE is identifying IP exhaustion quickly.

Unlike CPU or Memory exhaustion, Kubernetes rarely displays a simple message saying:

"No IP Addresses Available"

Instead, engineers must correlate symptoms from multiple components.

A common mistake is spending hours investigating:

- CPU Utilization
- Memory Utilization
- HPA
- KEDA
- Karpenter

when the real bottleneck is networking capacity.

---

# Symptom #1 - Pods Remain Pending

One of the earliest indicators is pods stuck in Pending state.

Example:

kubectl get pods

Result:

webapp-abc   Pending
webapp-def   Pending
webapp-xyz   Pending

At first glance, this may appear to be a scheduler issue.

However, networking capacity should also be investigated.

---

# Symptom #2 - Pod Events

Inspect pod events:

kubectl describe pod <pod-name>

Review the Events section.

Common indicators include:

FailedCreatePodSandBox

or

failed to setup network for sandbox

or

failed to assign an IP address

or

add cmd: failed to assign an IP address

These messages indicate that Kubernetes successfully scheduled the pod but the AWS VPC CNI was unable to provide networking resources.

---

# Symptom #3 - AWS VPC CNI Logs (aws-node)

The most important source of evidence is usually the AWS VPC CNI logs.

Identify the aws-node pod:

kubectl get pods -n kube-system | grep aws-node

Inspect logs:

kubectl logs -n kube-system <aws-node-pod>

Common error messages:

failed to allocate IP address

Datastore has no available IP addresses

Unable to allocate IP from subnet

Insufficient free addresses in subnet

These messages strongly indicate IP allocation problems.

---

# Symptom #4 - Verify Available Subnet Capacity

The definitive verification step is checking subnet capacity directly from AWS.

Command:

aws ec2 describe-subnets \
  --subnet-ids <subnet-id>

Look for:

AvailableIpAddressCount

Example:

{
  "AvailableIpAddressCount": 0
}

or

{
  "AvailableIpAddressCount": 3
}

Interpretation:

0-10 remaining addresses:
Critical

10-50 remaining addresses:
Warning

Healthy production environments should maintain significant spare capacity.

---

# Symptom #5 - Karpenter Node Launch Failures

If Karpenter is attempting to scale:

kubectl logs -n kube-system deployment/karpenter

Potential indicators:

failed launching instance

unable to create instance

insufficient free addresses

node launch failed

Karpenter may repeatedly attempt node provisioning while AWS rejects node creation due to subnet exhaustion.

---

# Symptom #6 - NodeClaims Created But Nodes Never Join

A common Karpenter troubleshooting scenario:

Karpenter:
Creates NodeClaim

AWS:
Fails EC2 Launch

Result:

NodeClaim exists

Node never joins cluster

Pods remain Pending

Investigating subnet availability often reveals the root cause.

---

# Symptom #7 - EC2 API Errors

AWS may explicitly report subnet exhaustion.

Examples:

InsufficientFreeAddressesInSubnet

or

Not enough free addresses available

These errors may appear in:

- CloudTrail
- EC2 Events
- AWS Console
- Terraform Apply Output

This is the strongest confirmation of subnet exhaustion.

---

# Complete Production Troubleshooting Workflow

A typical investigation path:

Traffic Spike
↓
KEDA Creates Pods
↓
Pods Remain Pending
↓
CPU Looks Healthy
↓
Memory Looks Healthy
↓
Inspect Pod Events
↓
Review aws-node Logs
↓
Check Karpenter Logs
↓
Verify AvailableIpAddressCount
↓
Identify Subnet Exhaustion
↓
Add Capacity Or New Subnets

---

# Interview Question

Question:

How would you diagnose subnet IP exhaustion in Amazon EKS?

Strong Answer:

I would begin by investigating Pending pods and reviewing pod events for networking-related failures.

Next, I would inspect AWS VPC CNI (aws-node) logs for IP allocation errors and review Karpenter logs for node launch failures.

Finally, I would validate subnet capacity using AvailableIpAddressCount from the EC2 API.

This allows me to distinguish networking exhaustion from CPU, memory, or scheduler-related issues and identify whether the root cause is node-level IP exhaustion, subnet exhaustion, or VPC capacity limitations.

---

Operational Lessons

Several important operational observations emerged during this analysis.

Networking Capacity Is A Scaling Resource

Many engineers focus exclusively on CPU and memory when planning Kubernetes capacity.

In Amazon EKS, networking resources such as ENIs, pod IPs, subnet capacity, and VPC address space are equally important.

Karpenter Cannot Solve Every Scaling Problem

Karpenter can provision additional nodes, but it cannot create IP addresses that do not exist.

If subnet capacity is exhausted, node provisioning itself may fail.

Prefix Delegation Improves Efficiency, Not Capacity

Prefix Delegation reduces AWS API calls and accelerates pod startup times.

However, it does not increase the total number of IP addresses available within a subnet.

Capacity Planning Must Include Networking

Production planning should include:

* CPU Capacity
* Memory Capacity
* Pod Density Limits
* ENI Limits
* Subnet Utilization
* VPC Address Utilization

Ignoring networking constraints frequently leads to unexpected scaling failures.

Monitoring Must Be Proactive

By the time subnet exhaustion becomes visible through Pending pods, user-facing impact may already be occurring.

Monitoring and alerting should be configured well before networking resources become constrained.

---

# Key Takeaway

One of the most important lessons in EKS operations is:

Healthy CPU does not guarantee healthy scaling.

Healthy Memory does not guarantee healthy scaling.

Pods require:

- CPU
- Memory
- IP Addresses

When IP resources are exhausted, applications may fail to scale even though compute resources appear completely healthy.

Therefore, networking capacity must always be included in Kubernetes capacity planning and production monitoring.