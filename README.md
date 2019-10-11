# OpenShift Container Platform v4 in a Lab Environment

## Abstract

This project describes (and implements) one way of deploying OCP4 nightly
builds in a minimal airgapped lab environment.

> **NOTE:** The container images required for an offline installation are
not included here. You will need to deploy OCP with internet access for the
``services`` VM at least once in order to "seed" the Nexus repository.
After that, you can repeat it as many times as you like with no internet
connectivity.

This is not an elaborate on how OpenShift installation works, how it should be
administered, and how the cluster is operated. Nor is it a document on how and
why any of the involved components work, and how to deploy or configure them.
There are other, much better references for that - see some of the links at the
end of this document.

However, if you do endeavour to read some of the playbooks and vars here, there
will be the occasional comment outlining quirks, gotchas, and pointing back to
this file.

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

## Software Requirements

This project uses Ansible to do most of its work, but obviously relies on some
additional external dependencies.

It was developed and initially tested on a macOS workstation acting as the
Ansible control node, but subsequent deployments and testing were taking place
on RHEL7, RHEL8, and even CentOS systems, so you should be good to go.

That being said, **the absolute minimum version of Ansible is 2.8**!

Additional software you will need before you proceed with your VMs:

 - RHEL 8.0 GA boot ISO image
 - RHEL CoreOS 42.80 boot and ostree images (I used 42.80.20190828.2)
 - Nexus Repository Manager OSS v3 UNIX archive (I used v3.19.1-01)
 - OpenVPN and PKCS11 Helper RPMs from EPEL8 and a client (optional)

For the control node, you will need the following:

 - OpenShift Installer nightly build (I used 4.2.0-0 20191007-203748)
 - OpenShift Client nightly build (same version as installer)

Eventually, once you did a connected installation, you can create a backup of Nexus repositories and include that 

## Configuration

Using Ansible obviously implies some things: it is expected that your control
node can communicate with, and authenticate against, any hosts you choose to
involve in this, and that privilege escalation is configured correctly.

The ``ansible.cfg`` files will probably work well unmodified, but you also
definitely want to have a look at the ``hosts`` inventory and customise it for
your needs and desires.

You *most definitely* want to have a look at the ``group_vars`` directory,
especially the ``all.yml`` file, because it contains all the important
configuration settings.

That being said, do not neglect to have a look at others - you may need to
change bits and pieces here and there.

## Additional Artifacts

There are a couple of playbooks that can also be used to configure underlying
host systems, but these are stashed away and most certainly not maintained to
the degree of the rest of this project.

> ***USE HOST CONFIGURATION PLAYBOOKS AT YOUR OWN RISK! YOU GET TO KEEP THE PIECES!***

## Links & References

TBD.

## Copyright, Copying & License

Copyright (c) Grega Bremec gregab@p0f.net, 2019 All rights reserved.

See the LICENSE file in this directory for more information.

