# SRE Failure Analysis Handbook
# AWS EKS | ALB | Kubernetes | KEDA | Karpenter

This handbook documents the most common production failure scenarios encountered in Kubernetes and Amazon EKS environments.

The goal is to understand:

- What the error means
- Who generated the error
- Why it occurs
- How to troubleshoot it
- How to recover from it
- Common interview questions

---

## Purpose

Production incidents rarely begin with a clear root cause.

Engineers are typically presented with symptoms such as:

- HTTP errors
- Increased latency
- Connection failures
- Pod restarts
- Failed deployments
- Scaling anomalies

The objective of this handbook is to provide a structured troubleshooting framework for identifying the component responsible for a failure and working backward toward the root cause.

Rather than memorizing individual error messages, engineers should learn to understand where failures originate within the request path and how different platform components behave under failure conditions.

---

# 1. HTTP 503 Service Unavailable

## What Is It?

HTTP 503 indicates that a gateway, load balancer, ingress controller, or application is temporarily unable to serve requests.

The keyword is:

TEMPORARILY

Unlike a 404 or 401, a 503 usually indicates that service may automatically recover once backend availability returns.

---

## Who Generates 503?

Always determine who generated the response.

Example:

HTTP/1.1 503 Service Temporarily Unavailable
Server: awselb/2.0

This tells us:

- Request reached ALB successfully
- DNS resolution succeeded
- Networking succeeded
- TLS termination succeeded
- ALB generated the error

The application never received the request.

---

## Most Common Cause In EKS

ALB
→ Target Group
→ No Healthy Targets

Result:

503 Service Unavailable

---

## Production Scenarios

### Scenario 1 - Bad Deployment

Version 1:
2 Healthy Pods

Deployment Starts

Old Pods Terminated

New Pods Fail Startup

Healthy Targets = 0

Result:

503

---

### Scenario 2 - Readiness Probe Failure

Pod Status:

Running

Pod Readiness:

False

Kubernetes removes pod from Service Endpoints.

ALB removes target from Target Group.

Result:

503

---

### Scenario 3 - Scale To Zero

Deployment replicas become 0.

No backend exists.

Result:

503

---

### Scenario 4 - Capacity Exhaustion

Traffic Spike
→ Thread Pools Saturated
→ Health Checks Timeout
→ Targets Removed

Result:

503

---

## Troubleshooting

kubectl get pods

kubectl get endpoints

kubectl describe ingress

kubectl describe pod

Target Group Health

Questions:

- Are pods running?
- Are pods ready?
- Are endpoints present?
- Are targets healthy?

---

## Recovery

Restore healthy targets.

ALB automatically resumes traffic.

---

## Interview Question

Q:
Pods are Running but users receive 503.

Why?

A:
Running does not mean Ready.

Readiness failures remove pods from service endpoints.

ALB sees no healthy targets and returns 503.

=================================================================

# 2. HTTP 502 Bad Gateway

## What Is It?

A gateway successfully receives a request.

A backend exists.

The backend returns an invalid response.

Gateway returns:

502 Bad Gateway

---

## Architecture

User
→ ALB
→ Backend Exists
→ Invalid Response
→ 502

---

## Common Causes

### Backend Crash During Request

Request arrives.

Application crashes before response.

Gateway receives connection reset.

Result:

502

---

### TLS Mismatch

Gateway expects HTTPS.

Backend speaks HTTP.

Result:

502

---

### Reverse Proxy Misconfiguration

NGINX
→ Backend Service

Backend configuration incorrect.

Result:

502

---

### Invalid HTTP Response

Backend sends malformed response.

Gateway cannot parse it.

Result:

502

---

## Troubleshooting

- Backend Logs
- NGINX Logs
- ALB Logs
- TLS Configuration
- Service Ports
- Endpoint Configuration

---

## Interview Question

Q:
Difference between 502 and 503?

A:

502:
Backend exists but communication fails.

503:
No healthy backend available.

=================================================================

# 3. HTTP 500 Internal Server Error

## What Is It?

Request successfully reaches the application.

Application cannot process request.

Application itself generates:

500 Internal Server Error

---

## Architecture

User
→ ALB
→ Application
→ Dependency Failure
→ 500

---

## Common Causes

### Unhandled Exception

Null Pointer Exception

Index Out Of Bounds

Logic Bug

Result:

500

---

### Database Failure

Application
→ Database

Database unavailable.

Application returns:

500

---

### Redis Failure

Application
→ Redis

Redis unavailable.

Application returns:

500

---

### Authentication Failure

JWT Validation

Token Parsing

Authorization Bug

Result:

500

---

## Important Observation

Pods may be:

Running
Ready
Healthy

Yet users still receive:

500

Scaling will not fix this problem.

---

## Troubleshooting

Application Logs

Database Health

Redis Health

External API Health

Recent Deployment Changes

---

## Interview Question

Q:
Why doesn't autoscaling fix a 500?

A:

Because application logic or dependencies are failing.

More replicas simply create more failing replicas.

=================================================================

# 4. Connection Refused

## What Is It?

Destination host is reachable.

Port is not accepting connections.

Failure occurs immediately.

---

## Mental Model

House exists.

Door exists.

Nobody answers.

Connection Refused.

---

## Common Causes

### Wrong Target Port

Service:

targetPort: 8080

Application:

Listening on 9090

Result:

Connection Refused

---

### Application Process Dead

Pod Running

Application Crashed

Result:

Connection Refused

---

### Wrong Container Port

Container expects:

8080

Application listening:

9090

Result:

Connection Refused

---

## Common Errors

Java:

java.net.ConnectException

Python:

ConnectionRefusedError

Go:

dial tcp:
connection refused

---

## Troubleshooting

kubectl describe svc

kubectl get endpoints

kubectl exec

netstat -tulpn

ss -tulpn

Verify:

- Process exists
- Correct port
- Correct targetPort

---

## Interview Question

Q:
Can a Pod be Running and still produce Connection Refused?

A:

Yes.

Container process may be dead while pod remains Running.

=================================================================

# 5. Connection Timeout

## What Is It?

Connection attempt receives no response.

Client waits until timeout.

---

## Mental Model

House exists.

Door exists.

You ring bell.

Nobody answers.

You wait.

Timeout.

---

## Common Causes

### Security Group Block

ALB
→ Node

Traffic denied.

Result:

Timeout

---

### Network Policy Block

Pod
→ Pod

Traffic denied.

Result:

Timeout

---

### NACL Block

Subnet
→ Subnet

Traffic denied.

Result:

Timeout

---

### Dependency Unreachable

Application
→ Database

No route.

Result:

Timeout

---

## Common Errors

Java:

SocketTimeoutException

Python:

TimeoutError

Go:

i/o timeout

---

## Troubleshooting

Security Groups

Route Tables

NACLs

Network Policies

DNS Resolution

Dependency Health

---

## Interview Question

Q:
Difference between Timeout and Refused?

A:

Refused:
Destination reached.
Port closed.
Immediate failure.

Timeout:
No response received.
Client waits until timeout.

=================================================================

# 6. Readiness vs Liveness Probes

## Liveness Probe

Question:

Should Kubernetes restart this container?

Failure:

Container restarted.

---

## Readiness Probe

Question:

Should this pod receive production traffic?

Failure:

Pod removed from service endpoints.

---

## Critical Observation

Pod Status:

Running

Readiness:

False

Users:

503

This is one of the most common Kubernetes outages.

---

## Interview Question

Q:
Can a Running pod still cause a production outage?

A:

Yes.

Running only means the process exists.

Readiness determines whether traffic is sent to the pod.

=================================================================

# 7. KEDA, HPA and Ownership

## Key Concept

Always identify the controller that owns a resource.

Example:

CloudWatch
→ KEDA
→ HPA
→ Deployment
→ ReplicaSet
→ Pods

---

=================================================================

# Kubernetes Ownership Model

One of the most important troubleshooting concepts in Kubernetes is understanding ownership.

Many engineers attempt to modify resources manually and are surprised when those changes are automatically reverted.

Example:

Deployment
    ↓
ReplicaSet
    ↓
Pods

Or

CloudWatch
    ↓
KEDA
    ↓
HPA
    ↓
Deployment
    ↓
ReplicaSet
    ↓
Pods

Controllers continuously reconcile actual state toward desired state.

As a result:

Manual changes are often temporary.

The controller owning the resource ultimately determines the final state.

During troubleshooting, identifying ownership is often more valuable than inspecting the resource itself.

----

## What We Observed

Manual Scale:

kubectl scale deployment webapp --replicas=0

KEDA:

minReplicaCount = 2

Result:

Pods recreated automatically.

---

## Lesson

In Kubernetes:

Manual state is temporary.

Controller state is authoritative.

---

## Interview Question

Q:
Why did the deployment return to 2 replicas after manual scaling?

A:

KEDA and HPA owned replica count and reconciled the deployment back to desired state.

=================================================================


=================================================================

# Common Failure Mapping

One of the fastest ways to troubleshoot an outage is to identify which layer of the platform is most likely responsible.

| Symptom | Most Likely Layer |
|----------|------------------|
| HTTP 503 | Load Balancer / Readiness / Capacity |
| HTTP 502 | Gateway / Reverse Proxy / Backend Communication |
| HTTP 500 | Application Logic / Dependencies |
| Connection Refused | Service Process / Port Configuration |
| Connection Timeout | Network Path / Security Controls |
| Pod Pending | Scheduler / Capacity / Networking |
| CrashLoopBackOff | Application Startup Failure |
| ImagePullBackOff | Registry / Authentication |
| Node NotReady | Infrastructure / Node Health |
| Failed Scheduling | Capacity / Taints / Networking |

This mapping should not replace investigation, but it provides a useful starting point during incident response.

====================================================

# Golden SRE Rule

# Incident Response Framework

During an outage, avoid jumping directly to conclusions.

Instead, follow a structured investigation process.

Step 1:
Who generated the error?

ALB?
Ingress?
Application?
Dependency?

Step 2:
Who owns the resource?

Deployment?
ReplicaSet?
HPA?
KEDA?
Karpenter?

Step 3:
What changed recently?

Deployment?
Configuration?
Scaling policy?
Infrastructure?

Step 4:
Are dependencies healthy?

Database?
Redis?
External API?
DNS?

Step 5:
Verify evidence before acting.

Always collect logs, events, metrics, and health information before making changes.

The fastest engineers are not the ones who troubleshoot first.

They are the ones who identify the correct failure domain first.


# Conclusion

The purpose of this handbook is not to memorize individual error codes.

The goal is to develop a systematic approach to diagnosing failures in distributed systems.

Most production incidents ultimately fall into a small number of categories:

- Availability failures
- Dependency failures
- Deployment failures
- Networking failures
- Capacity failures

Engineers who can quickly identify the layer responsible for a failure consistently resolve incidents faster than those who focus only on symptoms.

Understanding ownership, request flow, dependency chains, and controller behavior is often the difference between a five-minute diagnosis and a multi-hour outage investigation.