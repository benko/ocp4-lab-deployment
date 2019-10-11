# OpenShift Container Platform v4 in a Lab Environment

## Abstract

This document outlines a way of deploying OCP4 nightly builds in a minimal
airgapped lab environment.

## Topology

The topology of the lab rendered by this project is as follows:

 - 1 service VM running RHEL8 and the following:
    - a DNS server for the internal OCP zones
    - a DHCP/TFTP PXE boot environment for RHCOS
    - a HTTP server for RHCOS boot artifacts and other misc
    - an Haproxy load balancer for OCP install (and optionally, ingress)
    - a Nexus3 OSS Repository Manager for facilitating airgap
    - a NFS server to provide the cluster with storage
    - optionally, an OpenVPN service for dialing into the cluster
 - 1 master VM
 - 2 worker VMs
 - (transient) 1 bootstrap VM during OCP deployment

## System Requirements

The host system requirements for running the above are relatively modest - it
works (to a decent degree) within 24GB RAM, but will certainly not mind having
a bit extra on the side.

Individual VM recommendations are as follows:

 - service VM: 3GB, 1 core
 - master VM: 8GB, 4 cores
 - worker VM: 6GB, 4 cores
 - bootstrap VM: 4GB, 4 cores

Disk space is thin-provisioned, but defaults to 64GB per image.

## Additional Artifacts

There are a couple of playbooks that can also be used to configure underlying
host systems, but these are stashed away and most certainly not maintained to
the degree of the rest of this project.

***USE HOST CONFIGURATION PLAYBOOKS AT YOUR OWN RISK! YOU GET TO KEEP THE PIECES!***

## Copyright, Copying & License

Copyright (c) Grega Bremec gregab@p0f.net, 2019 All rights reserved.

See the LICENSE file in this directory for more information.

