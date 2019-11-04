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

## TL;DR

0. Go to [OpenShift Download Page](https://try.openshift.com/) and do your thing.
   Download stuff.
    - nightly installer build
    - nightly client build
    - RHCOS kernel and initrd
    - RHCOS bare metal image for both BIOS and UEFI
1. Get the rest of the stuff:
    - clone this project
    - download [Nexus3 OSS](https://www.sonatype.com/download-nexus-repo-oss)
    - get Nexus [configuration backup here](https://drive.google.com/file/d/1cXPqnoQEP8mWM9LjEsaA9N5GtjPbu3H0/view?usp=sharing)
    - get a RHEL8 image from the [Red Hat Developer Program](https://developers.redhat.com/)
    - if you decide to set up a vpn connection to services VM, [download it from EPEL8](https://epel.ip-connect.info/8/Everything/x86_64/Packages/) (see below for more)
    - put all of the above into ``binaries/`` directory in this project
2. Edit the ``[hypervisors]`` section of the hosts file to reflect your target
   hypervisor.
3. Look at the ``group_vars/all.yml`` file and:
    - choose a ``parent_domain`` and the ``cluster_name``
    - set ``fwd_dns_server`` to a working DNS that can resolve the interweb
    - set ``svc_default_gw`` to an actual working gateway
    - change ``ip_prefix`` if necessary (only in special cases though)
    - pick your networking type (``vm_use_bridge=yes`` or ``no``) and provide
      details
    - decide if you want services VM to have an additional interface and
      configure it (``vm_svc_add_interface``)
    - have a look at the VM catalog and see if anything stands out (shouldn't)
    - provide authorised user data and the pull secret at the end
4. Look at ``group_vars/rhel.yml`` and fill in your own information.
5. Make sure ``/etc/hosts`` (or some other means) can resolve at least the
   services VM
6. If you chose to not use OpenVPN, make sure you also add these to your
   resolver:
    - bootstrap
    - master
    - worker1
    - worker2
    - api (should point to services)
    - console-openshift-console.apps (should point to services)

    (the above are all qualified with ``cluster_name``.``parent_domain``)
7. Run the ``site.yml`` playbook.
8. Get coffee.
9. Read the rest of the document, particularly the section on Nexus
   configuration (and submit any issues).

## Topology

The topology of the lab rendered by this project is as follows:

 - 1 service VM running RHEL8 and the following:
    - a DNS server for the internal OCP zones and forwarding enabled
    - a DHCP/TFTP PXE boot environment for RHCOS
    - an HTTP server for RHCOS boot artifacts and other misc
    - an Haproxy load balancer for OCP install (and optionally, ingress)
    - a Nexus3 OSS Repository Manager for facilitating the airgap
    - an NFS server to provide the cluster with storage
    - optionally, an OpenVPN service for dialing into the cluster
 - 1 master VM
 - 2 worker VMs
 - (transient) 1 bootstrap VM during OCP deployment

## System Requirements

The host system requirements for running the above are relatively modest - it
deploys with 16GB RAM, and it works (to a decent degree) within 24GB RAM, but
will certainly not mind having you bump up the VM specs with a bit of extra on
the side.

Individual VM recommendations are as follows:

 - service VM: 3GB, 1 core
 - master VM: 8GB, 4 cores
 - worker VM: 6GB, 4 cores
 - bootstrap VM: 4GB, 4 cores

Disk space is thin-provisioned, but defaults to 64GB per system (single image).
Actual disk utilisation amounts to about 32GB immediately after the
installation, but will obviously grow.

## Software Requirements

This project uses Ansible to do most of its work, but obviously relies on some
additional external dependencies.

It was developed and initially tested on a macOS workstation acting as the
Ansible control node, but subsequent deployments and testing were taking place
on RHEL7, RHEL8, and even CentOS systems, so you should be good to go.

That being said, **the absolute minimum version of Ansible is 2.8**!

Some of the Ansible modules used require additional Python modules on the
control node, which might not be installed by default on your system, depending
on, of course, what it is.

TBD.

For the control node, you will also need the following from the
[Red Hat Cloud Management Dashboard](https://try.openshift.com/):

 - OpenShift Installer nightly build (I used 4.2.0-0 20191007-203748)
 - OpenShift Client nightly build (same version as installer)

Additional software you will need before you proceed with your VMs:

 - RHEL 8.0 GA boot ISO image (I suggest you join
   [Red Hat Developer Program](https://developers.redhat.com/) if
   you don't intend to use this for production, **which you shouldn't anyway**,
   because it's a totally unsupportable lab-only architecture)
 - RHEL CoreOS 42.80 boot and ostree images (I used 42.80.20190828.2, available
   from the [Cloud Management](https://try.openshift.com/)'s download page)
 - Nexus Repository Manager OSS v3 UNIX archive (I used v3.19.1-01, available
   from [Sonatype](https://www.sonatype.com/download-nexus-repo-oss))
 - OpenVPN and PKCS11 Helper RPMs
   [from EPEL8](https://epel.ip-connect.info/8/Everything/x86_64/Packages/) and
   a client (optional)

The one extra artifact that is unique to this project is the initial [backup of
Nexus configuration
database](https://drive.google.com/file/d/1cXPqnoQEP8mWM9LjEsaA9N5GtjPbu3H0/view).
It contains the proxy repository definitions for the upstream ``quay.io`` and
``registry.redhat.io`` registries, and some other minor configuration bits.
What it does ***not*** contain though, is authentication data which you will
have to extract out of your pull secret and feed to it. See below for more.

> NOTE: The configuration database backup does not include container images.
That is a separate backup called the blob backup, which you will be able to
create after the first successful installation and then use for any subsequent
deployments of this system.

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

### A Quirk!

At any rate, regardless of what kind of network model you decide to use, it is
your responsibility to make sure all the VM hostnames resolve correctly on the
control node, which becomes particularly important from the point where
services VM is up and running.

You have three general options:

 - add every single host to /etc/hosts (this will do for installation)
 - use the inventory option ``ansible_host`` (similar, but untested)
 - establish a vpn tunnel to services and use its DNS server

Obviously the latter has a clear advantage of being able to use the cluster
wildcard DNS domain after everything is up, and ingress will work just fine for
you. Read the Non-Bridged Networking and OpenVPN sections below for more if
that's what you want.

There may be reasons for you to decide against it, and it's fine - that's why
this is a configurable option. You can use whatever other option you wish to
fix the resolver.

At any rate, at some point you will see a notification after the services VM is
up and running, telling you to go to Nexus and configure authentication. That
is a sure sign the only thing between you and a cluster is just a couple of
additional steps.

Read below for more on Nexus configuration. You will need this to complete the
set-up successfully.

### Virtualization Host Configuration

This can go in any direction, really. Some basics:

 - yes, *libvirt* is a requirement
 - strongly advised, is a single bridge-based network

#### Non-Bridged Networking Considerations

For non-bridged networks, you will most certainly need two network interfaces
in the ``services`` VM, unless you are running the playbooks on the hypervisor
itself - in that case you probably have direct access to the virt network.

One of the interfaces would be configured by the playbook already - that's
fine. Keep it, as it allows your cluster hosts on the private network to
connect to the services VM whenever they need it.

For external access, indeed for *anything* beyond simply provisioning that
initial ``services`` VM, but not even configuring it, you will need an
additional directly accessible interface, and subsequently an OpenVPN listening
on it so you (and the playbooks) can get into the cluster.

The idea is your control node is an external client to the airgapped system, so
it needs a VPN connection to access the resources - a nice real-life scenario.

See the OpenVPN section below, ``group_vars/all.yml``, and the service
provisioning playbook for more on configuration.

### Playtime Configuration Variables

What you most probably want to have a look at in terms of enriching your
airgapped experience, is ``additional_content_sources``. It is an array of
simple double-attribute dictionaries:

    additional_content_sources:
      - registry_host: registry.redhat.io
        image_basename: rhel8/postgresql-96
      - registry_host: registry.redhat.io
        image_basename: rhscl/mysql-57-rhel7
      - registry_host: registry.redhat.io
        image_basename: redhat-openjdk-18/openjdk18-openshift

Do note that the only two proxy repositories defined as of now are ``quay.io``
and ``registry.redhat.io``. If your mirrored images are coming from somewhere
else, you will need to add a new proxy repository to Nexus configuration (and
modify the group repository on port 5000).

TODO: add stuff about why ``binary_artifact_path`` and ``cluster_rtdata_path`` have to be relative.

There are some other interesting variables that can override default behaviour
of some of the playbooks. Here's a non-exhaustive list:

 - ``x509_validity_until``

    We create a certificate authority as part of the installation. This
    variable must contain an absolute date in format ``YYYYMMDDhhmmssZ``.

    The reason validity is an absolute date is because with a relative date,
    all cert-related operations become non-idempotent.

    > NOTE: All generated certificates will use this expiration date.

 - ``vm_use_bridge``

    Decides whether to use a bridged interface or one attached to a libvirt
    network in the corresponding guest configuration. Obviously, you would want
    to stick to the same setting in all VMs, but if you need to discriminate, I
    suggest ``host_vars``, however ugly that is.

    There are two settings that go along with that - ``vm_bridge_name`` and
    ``vm_network_name``, but they are of course mutually exclusive. The former
    is only used when ``vm_use_bridge`` is on, and vice-versa.

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

 - ``force_hd_image_recreate=yes``

    This will kill any existing disk image in VM provisioning playbooks and
    force them to be recreated from scratch.

TODO: add something about default gateway and why it needs to be broken, but not with OpenVPN.

### Useful Tags

While (re)running the playbooks, some tags may be of particular use because
they simply save time. Such as:

 - ``rhsm``

    Skipping this tag will skip any subscription-related action. RHSM can be
    slow, and this just skips those slow steps, but if you never did it before,
    it also prevents your services VM from being updated with the latest
    package goodness, and will most certainly break any additional software
    installations. So in short, do it once, then start skipping it.

 - ``openvpn``

    While configuring the ``services`` VM, you might not want to deploy an
    OpenVPN service, for whatever reason, so skipping this tag allows you to
    simply not even care about the RPMs this would normally use, much less
    about the configuration of the service and any other bollocks. It does
    mean, however, that you need to eat your own DNS food. ``/etc/hosts`` FTW!

 - ``nexus_restore``

    If you already did a restore of the Nexus Repository Manager and you're
    just re-running the services config playbook for some reason other than
    firstboot, you might want to prevent it from restoring everything all over
    again and skip any task bearing this tag.

 - ``kick_bootstrap``

    If you're planning on redeploying the cluster several times in a very short
    period of time, it might make sense to keep the bootstrap VM as a member of
    load balancing groups in haproxy. Skipping this tag will allow you do it.

 - ``services_vm``

    When running the master ``site.yml`` playbook, when you get to the point
    where the services VM is up, but you need more time than what you are
    given, you can interrupt the execution and then resume at an arbitrary
    point in the future *without re-running* services VM provisioning and
    configuration by just skipping this tag.

## Notes on OpenVPN

As already mentioned, OpenVPN has an advantage over other resolver setup
options in that the services VM is set up to resolve your cluster to begin
with, and it's also able to use the cluster wildcard DNS domain after
everything is up, and ingress will work just fine for you.

That is because it comes with a DNS server it is willing to share with you, so
when you establish a VPN connection to it, you can simply tell your client to
use its DNS as the primary DNS for your workstation (it is preconfigured to
relay any queries for non-authoritative zones back to your original DNS - that
is, if you put it into ``all.yml`` file).

The network configuration for cluster VMs has to change a bit with OpenVPN,
though.  After all, you want to be getting a response from the VMs, right? So
they need to have the correct default gateway set.

So this time around, as opposed to giving the VMs a bogus default gateway, we
need to set it to the actual services VM IP address.

Also, for the purposes of being able to run the services VM configuration
playbook, you are still required to have the services VM in /etc/hosts
somewhere.

There is also this critical moment *after* the services VM is already
configured, where you have to actually remember to start up a VPN client and
configure it correctly.

You will see a message and will be given a pause that will allow you to do
everything needed before the playbook continues, and give you instructions on
what to do if you want to just interrupt the execution and continue from where
you left off after a while.

TODO: where are the certs for the client?

TODO: example openvpn client config

## Additional Artifacts

There are a couple of playbooks that can also be used to configure underlying
host systems, but these are stashed away and most certainly not maintained to
the degree of the rest of this project.

> ***USE HOST CONFIGURATION PLAYBOOKS AT YOUR OWN RISK! YOU GET TO KEEP THE PIECES!***

## Other Nasty Bugs That Bite

### Time Synchronisation Between Control Node and Hypervisors

You read it correctly. Ignition files are created on the control node.
Hypervisors, on the other hand, set the time for VMs. If the two do not match,
bootstrap will have appeared to boot normally, but the other nodes will refuse
to download their configuration from it, producing an error message like this
on the console:

    x509: certificate has expired or is not yet valid

While I agree that the message could hardly be more ambiguous (maybe if it just
said, "SUCCESS: certificate exists"?) this is not the matter of discussion
here. Fix your time sync.

[This is the RH knowledge base explanation of the problem.](https://access.redhat.com/solutions/4355651)

### RHEL8

#### Bridged Networking

Network bridges in RHEL8 behave really, *really*, **REALLY** odd.

So don't be surprised if you can't contact the VM host on the bridged IP until
*it* contacts you first. We'll send our people to talk to your people.

#### Other Weird Behaviour

These are still to be researched, but have occurred:

 - ``fatal: [services.lab.example.com]: FAILED! => {"changed": false, "msg": "Wrong or empty passphrase provided for private key"}``

    This is ``openssl_certificate`` module on crack. It was happy to sign the
    cert on all hosts but one RHEL8 machine, even after a complete package
    update.

    It seems the [root cause](https://github.com/ansible/ansible/issues/55495) is actually a bug.

    Augmented the task with ``select_crypto_backend=pyopenssl``.

    Unfortunately, I've yet to test how well this works on RHEL7 then.

    TODO: test pyopenssl on rhel7. there. done.

 - ``coreos-installer[]: failed fetching image headers from http://services.lab.example.com/rhcos-x.y.z-w-metal-bios.raw.gz``

    What can I say. Bridged network on a RHEL8 host? The services VM was fine,
    the network was there, but the bootstrap node wasn't cooperating.

## Links & References

TBD.

## Copyright, Copying & License

Copyright (c) Grega Bremec gregab@p0f.net, 2019 All rights reserved.

See the LICENSE file in this directory for more information.

