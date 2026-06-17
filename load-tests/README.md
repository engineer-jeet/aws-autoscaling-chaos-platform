Load Testing

This directory contains load-testing assets used to validate autoscaling and capacity-planning assumptions.

Tooling

The project uses k6 to generate HTTP traffic against workloads running on Amazon EKS.

Objectives

The tests were designed to validate:

* Request-driven autoscaling
* KEDA scaling behavior
* Horizontal Pod Autoscaler reactions
* Karpenter node provisioning
* Capacity-planning assumptions
* Platform stability under increasing load

The primary objective was not to determine the maximum throughput of the application. Instead, the focus was understanding how the platform responds to changing demand and how scaling components interact under load.

Structure

k6/

Contains k6 scripts used to generate traffic during validation exercises.

Example:

* webapp-basic.js – basic HTTP workload used to trigger scaling events and validate platform behavior.

Example Usage

k6 run webapp-basic.js

Notes

Load-testing results and capacity-planning observations are documented in the repository’s documentation directory.


Users can run:

BASE_URL=http://my-alb.amazonaws.com k6 run webapp-basic.js
