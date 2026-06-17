Error Engineering and Failure Analysis in Amazon EKS

Overview

Reliable systems are not defined by the absence of failures. They are defined by how quickly failures can be detected, understood, and resolved.

As part of the AWS Autoscaling and Resilience Platform project, multiple failure scenarios were analyzed to understand how production systems fail, how failures manifest to users, and how engineers should approach troubleshooting and recovery.

The objective was not simply to generate HTTP errors, but to answer several operational questions:

* Where did the failure originate?
* Which component generated the error?
* How does the failure appear to users?
* How can the root cause be identified?
* What actions are required to restore service?

Understanding these questions is a fundamental part of Site Reliability Engineering and production operations.

⸻

Test Environment

The following architecture was used throughout the failure analysis exercises.

User
    ↓
AWS Application Load Balancer
    ↓
Kubernetes Ingress
    ↓
Kubernetes Service
    ↓
NGINX Pods
    ↓
Amazon EKS

Autoscaling components deployed in the environment included:

* KEDA
* Horizontal Pod Autoscaler (HPA)
* Karpenter
* Spot NodePools
* On-Demand NodePools

The objective was to analyze failures across multiple layers of the platform rather than focusing solely on application behavior.

⸻

Lab 1 – HTTP 503 Service Unavailable

Objective

Generate a real production-style HTTP 503 error and identify which component was responsible for generating the response.

⸻

Healthy Request Flow

User
    ↓
ALB
    ↓
Target Group
    ↓
Healthy Pods
    ↓
HTTP 200

⸻

Failure Scenario

The application deployment was intentionally scaled to zero replicas.

Before doing so, KEDA autoscaling was disabled:

kubectl delete scaledobject webapp-alb-scaler

This automatically removed the associated Horizontal Pod Autoscaler.

Verification:

kubectl get hpa

The deployment was then scaled to zero:

kubectl scale deployment webapp --replicas=0

Verification:

kubectl get deployment webapp
kubectl get pods

Result:

Deployment Replicas: 0
Pods Running: 0

⸻

Observed Result

Request:

curl -i http://<alb-endpoint>

Response:

HTTP/1.1 503 Service Temporarily Unavailable
Server: awselb/2.0

The most important observation was:

Server: awselb/2.0

This confirms:

* The application did not generate the error.
* Kubernetes did not generate the error.
* AWS Application Load Balancer generated the error.

The ALB had no healthy backend targets available.

⸻

Failure Flow

User
    ↓
ALB
    ↓
Target Group
    ↓
No Healthy Targets
    ↓
HTTP 503

⸻

Why HTTP 503 Happens In Production

Failed Deployment

A deployment begins.

Old pods terminate successfully.

New pods fail startup.

Result:

Healthy Targets = 0

Users receive:

HTTP 503 Service Unavailable

⸻

Readiness Probe Failure

Pods may be running but fail readiness checks.

Kubernetes removes them from service endpoints.

The load balancer sees no healthy targets.

Result:

HTTP 503

⸻

Accidental Scale-To-Zero

Replica count becomes zero.

No application instances remain available.

Result:

HTTP 503

⸻

Capacity Exhaustion

Traffic exceeds application capacity.

Pods become overloaded.

Health checks begin failing.

Targets are removed.

Result:

HTTP 503

⸻

Node Failures

All replicas are running on failed nodes.

Target groups lose healthy endpoints.

Result:

HTTP 503

⸻

Troubleshooting Checklist

Kubernetes:

kubectl get pods
kubectl get deployment
kubectl get endpoints
kubectl get ingress
kubectl describe ingress

AWS:

* Target Group Health
* ALB Target Registration
* Health Check Status

Questions to ask:

* Are pods running?
* Are pods ready?
* Do service endpoints exist?
* Does the target group contain healthy targets?

⸻

Recovery

Restore application replicas:

kubectl scale deployment webapp --replicas=2

Verify pod readiness.

Retest:

curl http://<alb-endpoint>

Result:

HTTP 200 OK

Service availability is restored.

⸻

Connection Refused

Definition

Connection Refused occurs when the destination host is reachable but no application is accepting connections on the requested port.

The TCP connection fails immediately.

⸻

Request Flow

Client
    ↓
Host Reachable
    ↓
Port Closed
    ↓
TCP Reset (RST)
    ↓
Connection Refused

⸻

Common Causes

Incorrect Target Port

Service configuration:

targetPort: 8080

Application:

Listening on 9090

Result:

Connection Refused

⸻

Application Crash

Pod exists.

Container is running.

Application process inside the container has terminated.

Result:

Connection Refused

⸻

Incorrect Container Port

Kubernetes expects one port.

Application listens on another.

Result:

Connection Refused

⸻

Typical Error Messages

Java:

java.net.ConnectException: Connection refused

Python:

ConnectionRefusedError

Go:

dial tcp: connection refused

⸻

Troubleshooting

kubectl describe svc
kubectl get endpoints
kubectl exec -it <pod> -- sh

Inside the container:

netstat -tulpn

or

ss -tulpn

Verify:

* Is the process running?
* Is it listening on the correct port?
* Does targetPort match containerPort?

⸻

Connection Timeout

Definition

Connection Timeout occurs when a connection attempt receives no response.

The client waits until its timeout threshold is reached.

Unlike Connection Refused, the destination may never receive the request.

⸻

Failure Flow

Client
    ↓
Network Path
    ↓
Packet Drop
    ↓
No Response
    ↓
Timeout

⸻

Common Causes

Security Group Restrictions

Traffic is blocked before reaching the destination.

Result:

Connection Timeout

⸻

Network Policy Restrictions

Kubernetes network policies deny communication.

Result:

Connection Timeout

⸻

Network ACL Restrictions

Subnet-level filtering blocks packets.

Result:

Connection Timeout

⸻

External Dependency Failure

Applications attempt to connect to databases or external services.

No response is received.

Result:

Connection Timeout

⸻

Typical Error Messages

Java:

SocketTimeoutException

Python:

TimeoutError

Go:

i/o timeout

⸻

Troubleshooting Areas

* Security Groups
* Network ACLs
* Route Tables
* Network Policies
* DNS Resolution
* Dependency Health
* VPC Reachability

⸻

HTTP 500 Internal Server Error

Definition

The request successfully reaches the application.

The application itself cannot process the request.

The application generates the error.

⸻

Typical Request Flow

User
    ↓
ALB
    ↓
Pod
    ↓
Database

Database becomes unavailable.

Application returns:

HTTP 500 Internal Server Error

⸻

Common Causes

* Application bugs
* Unhandled exceptions
* Database failures
* Redis failures
* Dependency failures
* Authentication failures
* Configuration errors

⸻

Important Observation

Pods may be:

* Running
* Ready
* Healthy

Yet users still receive:

HTTP 500

Adding additional pods does not solve the problem.

Scaling does not solve the problem.

Root cause analysis is required.

⸻

HTTP 502 Bad Gateway

Definition

A gateway successfully receives a request but receives an invalid response from the backend service.

The gateway generates:

HTTP 502 Bad Gateway

⸻

Common Causes

* Reverse proxy misconfiguration
* Backend connection reset
* TLS mismatch
* Invalid HTTP responses
* Backend crash during request processing

⸻

Request Flow

User
    ↓
ALB
    ↓
Backend Exists
    ↓
Invalid Response
    ↓
HTTP 502

⸻

Production SRE Mental Model

During an outage, troubleshooting should follow a structured approach.

Step 1

Identify who generated the error.

Questions:

* ALB?
* Ingress?
* Application?

⸻

Step 2

Determine whether healthy targets exist.

⸻

Step 3

Verify pod readiness.

⸻

Step 4

Review recent deployments and changes.

⸻

Step 5

Validate dependency health.

Examples:

* Database
* Redis
* External APIs
* Authentication Services

⸻

Key Lessons Learned

Running Pods Do Not Guarantee A Healthy Service

Application health extends beyond pod status.

⸻

Healthy Nodes Do Not Guarantee Application Availability

Infrastructure can be healthy while applications remain unavailable.

⸻

Load Balancers Can Generate Errors Independently

Not every HTTP error originates from application code.

⸻

Most Kubernetes Outages Involve A Small Set Of Failure Categories

Common sources include:

* Deployments
* Readiness failures
* Dependency failures
* Networking failures
* Capacity exhaustion

⸻

Ownership Matters

Always identify the controller responsible for the resource.

Examples:

* Deployment
* HPA
* KEDA
* Karpenter

Understanding ownership dramatically reduces troubleshooting time.

⸻

Lab Outcome

The exercises successfully reproduced and analyzed:

* Real AWS ALB 503 Service Unavailable responses
* Scale-to-zero outages
* Autoscaler ownership and reconciliation behavior
* Connection Refused scenarios
* Connection Timeout scenarios
* HTTP 500 Internal Server Error analysis
* HTTP 502 Bad Gateway analysis

These scenarios represent some of the most common production failure patterns encountered in Amazon EKS environments and provide a practical foundation for troubleshooting cloud-native systems at scale.