Project Summary

## Key Results

- Built a production-inspired Amazon EKS platform using Terraform, KEDA, Karpenter, ALB, and CloudWatch.
- Implemented request-driven autoscaling using ALB RequestCountPerTarget metrics.
- Validated autoscaling behavior under load using k6.
- Successfully sustained approximately 1,125 requests per second during testing.
- Analyzed common production failure modes including HTTP 503, connection timeouts, connection refused, Spot interruptions, and IP exhaustion scenarios.
- Documented operational runbooks and troubleshooting workflows for real-world SRE incidents.

Overview

                        +------------------+
                        |      Users       |
                        +---------+--------+
                                  |
                                  v
                     +------------------------+
                     | AWS Application LB     |
                     +-----------+------------+
                                 |
                                 v
                      CloudWatch Metrics
                                 |
                                 v
                               KEDA
                                 |
                                 v
                                HPA
                                 |
                                 v
                       Kubernetes Pods
                                 |
                                 v
                            Karpenter
                                 |
                                 v
                       EC2 Worker Nodes

This project was built to explore and implement production-grade autoscaling, capacity management, and resilience engineering concepts on Amazon EKS.

The primary objective was not simply to deploy Kubernetes workloads, but to understand how modern cloud-native platforms respond to changing demand, infrastructure failures, networking constraints, and scaling events.

The platform combines Infrastructure as Code, Kubernetes-native autoscaling, cloud-native observability, and failure analysis to simulate scenarios commonly encountered by Site Reliability Engineers and Platform Engineers operating large-scale distributed systems.

The project focuses on understanding not only how systems scale, but also how and why they fail.

----

Engineering Goals

The project was designed around four primary objectives:

1. Understand how modern Kubernetes platforms scale.
2. Study how infrastructure behaves under resource pressure.
3. Analyze common production failure patterns.
4. Explore the relationship between application scaling and infrastructure scaling.

The focus was intentionally placed on operational behavior rather than application complexity.

⸻

Problem Statement

Modern applications experience highly variable traffic patterns.

Traditional static infrastructure often leads to one of two problems:

1. Under-provisioning, resulting in outages, high latency, and degraded user experience.
2. Over-provisioning, resulting in unnecessary infrastructure costs.

The challenge is to create a platform capable of dynamically adjusting both application capacity and infrastructure capacity based on demand while maintaining reliability and operational efficiency.

This project explores that challenge using Amazon EKS, KEDA, Karpenter, CloudWatch, and AWS Application Load Balancers.

⸻

Architecture

The platform is built on AWS and consists of the following major components:

Infrastructure Layer

* Amazon VPC
* Public and Private Subnets
* NAT Gateway
* IAM Roles and Policies
* Amazon EKS Cluster

Application Layer

* NGINX-based web application
* Kubernetes Services
* Kubernetes Ingress

Traffic Management

* AWS Application Load Balancer
* AWS Load Balancer Controller

Autoscaling Layer

* KEDA
* Horizontal Pod Autoscaler (HPA)
* Karpenter

Monitoring and Metrics

* Amazon CloudWatch
* ALB RequestCountPerTarget metrics

Testing Layer

* k6 Load Testing

All infrastructure components were provisioned using Terraform.

⸻

Key Design Decisions

Request-Based Autoscaling

Many Kubernetes environments rely exclusively on CPU and memory metrics for scaling decisions.

In real-world production environments, user traffic often increases before CPU utilization becomes a meaningful signal.

To address this, KEDA was configured to scale workloads using CloudWatch metrics derived from Application Load Balancer traffic.

Scaling decisions were therefore based on actual incoming requests rather than resource utilization alone.

Dynamic Infrastructure Provisioning

Pod scaling alone is insufficient if the cluster lacks available capacity.

Karpenter was integrated to provision worker nodes automatically whenever unschedulable pods were detected.

This allows application scaling and infrastructure scaling to work together.

Infrastructure as Code

All core AWS resources were provisioned using Terraform.

This ensured repeatable deployments, version-controlled infrastructure, and easier lifecycle management.

⸻

Autoscaling Workflow

The platform follows the following scaling lifecycle:

Traffic Increase

↓

Application Load Balancer Receives Additional Requests

↓

CloudWatch Metrics Increase

↓

KEDA Detects Increased Demand

↓

Horizontal Pod Autoscaler Increases Replica Count

↓

New Pods Are Created

↓

Karpenter Detects Scheduling Pressure

↓

Additional Worker Nodes Are Provisioned

↓

Traffic Stabilizes

The reverse process occurs during periods of reduced traffic, allowing infrastructure costs to decrease automatically.

⸻

Load Testing

Load testing was performed using k6 to validate autoscaling behavior.

The objective was not to identify the maximum throughput of the application, but rather to observe how the platform reacted to increasing traffic and whether autoscaling components behaved as expected.

Load testing validated the complete autoscaling workflow, demonstrating successful interaction between CloudWatch, KEDA, HPA, Kubernetes scheduling, and Karpenter-based node provisioning under increasing traffic demand.

The exercise demonstrated:

* Successful metric collection from CloudWatch
* KEDA-triggered scaling events
* HPA integration
* Dynamic pod scaling
* Dynamic node provisioning

⸻

Failure Engineering

A significant portion of the project focused on understanding common production failure modes.

Rather than simply deploying workloads, multiple failure scenarios were analyzed to understand root causes, symptoms, and recovery strategies.

HTTP 503 Errors

Scenarios were created where no healthy backend targets were available behind the load balancer.

This demonstrated how AWS ALB behaves when requests cannot be routed to healthy application instances.

Key learning:

A 503 error often indicates capacity or availability issues rather than application bugs.

Connection Refused

TCP-level connection failures were studied to understand situations where a destination host is reachable but no process is listening on the requested port.

Key learning:

Connection Refused typically indicates an application or service availability problem rather than a network problem.

Connection Timeout

Network path failures and packet drops were analyzed.

Key learning:

Connection Timeouts generally indicate networking issues such as routing problems, firewall restrictions, security group rules, network ACLs, or infrastructure instability.

Spot Interruption Analysis

The lifecycle of AWS Spot interruptions was reviewed, including:

* Interruption Notices
* Rebalance Recommendations
* Node Draining
* Pod Eviction
* Workload Recovery

The exercise provided insight into operating mixed Spot and On-Demand Kubernetes environments.

⸻

Capacity Planning

Capacity planning was explored from both application and infrastructure perspectives.

The project examined:

* CPU utilization
* Memory utilization
* Pod density
* Node capacity
* Request rates
* Scaling thresholds

One key takeaway was that autoscaling and capacity planning solve different problems.

Autoscaling determines how capacity is added or removed.

Capacity planning determines how much capacity is required under expected and failure conditions.

⸻

IP Exhaustion Engineering

One of the most valuable areas of exploration involved Amazon EKS networking limits.

Topics studied included:

* Elastic Network Interfaces (ENIs)
* Pod density limits
* Subnet capacity
* VPC address management
* Prefix Delegation
* Karpenter subnet discovery

The project highlighted that Kubernetes scaling can fail even when CPU and memory resources remain available if networking resources become exhausted.

This is a common operational challenge in large EKS environments.

⸻

Lessons Learned

Several important engineering lessons emerged from the project.

Scaling Is More Than CPU

CPU-based scaling alone is often insufficient.

Request rates, concurrency, queue depth, and business metrics frequently provide more meaningful scaling signals.

Capacity Exists At Multiple Layers

Application performance depends on more than compute resources.

Potential bottlenecks include:

* CPU
* Memory
* Node capacity
* Pod density
* ENI limits
* Subnet capacity
* Load balancer limits

Failure Analysis Is Essential

Understanding why systems fail is often more valuable than understanding how they work under ideal conditions.

Studying production failure modes provides deeper operational insight than successful deployments alone.

Platform Components Must Work Together

Successful autoscaling requires coordination across multiple systems:

* CloudWatch
* KEDA
* HPA
* Scheduler
* Karpenter
* EC2

A failure at any stage can impact the entire scaling workflow.

⸻

Operational Perspective

One of the most important outcomes of this project was recognizing that successful scaling is rarely limited by a single component.

Application performance depends on the interaction between:

- Traffic patterns
- Load balancers
- Metrics systems
- Autoscalers
- Schedulers
- Node provisioning systems
- Networking resources

Production incidents often occur when one of these layers becomes constrained while the others appear healthy.

Understanding these interactions is a critical skill for Platform Engineers and Site Reliability Engineers.

-----

Future Roadmap

This project focused primarily on stateless workloads and infrastructure scaling.

Future work will explore stateful distributed systems and data-layer resilience, including:

- StatefulSets
- Persistent Volumes
- Database replication
- Read replicas
- Eventual consistency
- Distributed transactions
- Multi-AZ architectures
- Multi-region architectures
- Disaster recovery
- Global traffic routing
- DNS failover strategies

The goal is to extend the platform from application autoscaling into distributed systems reliability and large-scale data architecture.

----

Project Outcomes

The platform successfully demonstrated:

- Request-driven autoscaling
- Dynamic node provisioning
- Capacity planning techniques
- Failure engineering practices
- EKS networking constraints
- Spot interruption analysis
- Production-style troubleshooting workflows

More importantly, the project provided practical experience operating a Kubernetes platform rather than simply deploying workloads onto Kubernetes.

----

Conclusion

This project evolved from a Kubernetes deployment exercise into a broader study of autoscaling, reliability engineering, capacity planning, and production operations.

The result is a production-inspired AWS EKS platform that demonstrates how modern cloud-native systems scale, recover, and operate under changing demand and failure conditions.

More importantly, the project provided practical insight into the engineering trade-offs involved in building reliable and cost-efficient distributed systems.