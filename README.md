# OpenShift Container Platform v4 in a Lab Environment

## Abstract

This project describes (and implements) one way of deploying OCP4 nightly
builds in a minimal airgapped lab environment.

This is not an elaborate on how OpenShift installation works, how it should be
administered, and how the cluster is operated. Nor is it a document on how and
why any of the involved components work, and how to deploy or configure them.
There are other, much better references for that - see some of the links at the
end of this document.

However, if you do endeavour to read some of the playbooks and vars here, there
will be the occasional comment outlining quirks, gotchas, and pointing back to
this file.

> **NOTE:** The container images required for an offline installation are
not included here. You will need to deploy OCP with internet access for the
``services`` VM at least once in order to "seed" the Nexus repository.
After that, you can repeat it as many times as you like with no internet
connectivity.

## Topology

The topology of the lab rendered by this project is as follows:

 - 1 service VM running RHEL8 and the following:
    - a DNS server for the internal OCP zones and forwarding enabled
    - a DHCP/TFTP PXE boot environment for RHCOS
    - a HTTP server for RHCOS boot artifacts and other misc
    - an Haproxy load balancer for OCP install (and optionally, ingress)
    - a Nexus3 OSS Repository Manager for facilitating the airgap
    - an NFS server to provide the cluster with storage
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

Disk space is thin-provisioned, but defaults to 64GB per system (single image).

## Software Requirements

This project uses Ansible to do most of its work, but obviously relies on some
additional external dependencies.

It was developed and initially tested on a macOS workstation acting as the
Ansible control node, but subsequent deployments and testing were taking place
on RHEL7, RHEL8, and even CentOS systems, so you should be good to go.

That being said, **the absolute minimum version of Ansible is 2.8**!

Some of the Ansible modules used require additional Python modules on the
control node, which might not be installed by default on your system.

TBD.

For the control node, you will also need the following:

 - OpenShift Installer nightly build (I used 4.2.0-0 20191007-203748)
 - OpenShift Client nightly build (same version as installer)

Additional software you will need before you proceed with your VMs:

 - RHEL 8.0 GA boot ISO image
 - RHEL CoreOS 42.80 boot and ostree images (I used 42.80.20190828.2)
 - Nexus Repository Manager OSS v3 UNIX archive (I used v3.19.1-01)
 - OpenVPN and PKCS11 Helper RPMs from EPEL8 and a client (optional)

Eventually, once you did a connected installation, you can create a backup of
Nexus repositories and include that in your future deployments.

## Configuration

### Control Node Configuration

Using Ansible obviously implies some things: it is expected that your control
node can communicate with, and authenticate against, any hosts you choose to
involve in this, and that privilege escalation is configured correctly.

The ``ansible.cfg`` file will probably work well unmodified, but you definitely
want to have a look at the ``hosts`` inventory and customise it for your needs
and desires.

You *most definitely* also want to have a look at the ``group_vars`` directory,
especially the ``all.yml`` file, because it contains all the important
configuration settings.

That being said, do not neglect to have a look at the other var files - you may
need to change bits and pieces here and there.

### Virtualization Host Configuration

This can go in any direction, really. Some basics:

 - yes, *libvirt* is a requirement
 - strongly advised, is a single bridge-based network

#### Non-Bridged Networking Considerations

For non-bridged networks, you will most certainly need two network interfaces
in the ``services`` VM.

One of the interfaces would be configured by the playbook already - that's
fine. Keep it, as it allows your cluster hosts on the private network to
connect to the services VM whenever they need it.

For external access, indeed for *anything* beyond simply provisioning that
initial ``services`` VM, but not even configuring it, you will need an
additional directly accessible interface, and subsequently OpenVPN listening on
it so you can get into the cluster.

The idea is your laptop is an external client to the airgapped system, so it
needs a VPN connection to access the resources - a nice real-life scenario.

See the section below and the service provisioning playbook for more on
configuration; bottom line, you will need to add the bridged iface manually
after installation.

### Playtime Configuration Variables

There are some interesting variables that can override default behaviour of
some of the playbooks. Here's a non-exhaustive list:

 - ``x509_validity_until``

    We create a certificate authority as part of the installation. This
    variable must contain an absolute date in format ``YYYYMMDDhhmmssZ``.

    The reason validity is an absolute date is because with a relative date,
    all cert-related operations become non-idempotent.

    > NOTE: All generated certificates will use this expiration date.

 - ``force_hd_image_recreate=yes``

    This will kill any existing disk image in VM provisioning playbooks and
    force them to be recreated from scratch.

 - ``vm_use_bridge``

    Decides whether to use a bridged interface or one attached to a libvirt
    network in the corresponding guest configuration. Obviously, you would want
    to stick to the same setting in all VMs, but if you need to discriminate, I
    suggest ``host_vars``, however ugly that is.

    There are two settings that go along with that - ``vm_bridge_name`` and
    ``vm_network_name``, but they are of course mutually exclusive. The former
    is only used whn ``vm_use_bridge`` is on, and vice-versa.

 - ``vm_svc_add_interface``

    Allows you to provision the services VM with an additional network
    interface that is connected to a bridge, rather than a private libvirt
    network. This, in turn, allows you to establish a VPN tunnel to it, gain
    access to the cluster network, and (given the correct client settings) use
    the services VM DNS in its full glory.

    Again, there are several settings that go with it:

    - ``vm_svc_add_bridge_name``: the bridge to enslave the interface to
    - ``vm_svc_add_macaddr``: what you think it is
    - ``vm_svc_add_ipaddr``: what you think it is
    - ``vm_svc_add_netmask``: what you think it is

 - ``ovpn_enforce_dhparam``

    A chance OpenVPN setting: normally we'll run without DH params, which
    enforces ECDS. If your client can't speak it, you should really update
    to a newer OpenSSL library. But in the mean time, set this to "yes" and
    a dh.pem file will be generated for you.

N.B.: add something about default gateway and why it needs to be broken.

### Useful Tags

While (re)running the playbooks, some tags may be of particular use because
they simply save time. Such as:

 - ``rhsm``

    Skipping this tag will skip any subscription-related action. RHSM can be
    slow, and this just skips those slow steps.

 - ``openvpn``

    While configuring the ``services`` VM, you might not want to deploy an
    OpenVPN service, for whatever reason, so skipping this tag allows you to
    simply not even care about the RPMs this would normally use, much less
    about the configuration of the service and any other bollocks. It does
    mean, however, that you need to eat your own DNS food. /etc/hosts FTW!

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

