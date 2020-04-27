oci-compute
===========

A python script to provision compute instances on [Oracle Cloud Infrastructure](https://www.oracle.com/cloud/) (OCI) using the [Python SDK](https://docs.cloud.oracle.com/en-us/iaas/Content/API/SDKDocs/pythonsdk.htm).

# About

This project illustrates the use of the [OCI Python SDK](https://docs.cloud.oracle.com/en-us/iaas/Content/API/SDKDocs/pythonsdk.htm) to list, provision, start, shutdown and terminate OCI compute instances.

Interaction with OCI from the command line can easily be achieved using the [OCI CLI](https://docs.cloud.oracle.com/iaas/Content/API/Concepts/cliconcepts.htm).
It is the perfect tool for most tasks, but handling output from the OCI CLI in shell scripts can be cumbersome for complex queries.
The [OCI Python SDK](https://docs.cloud.oracle.com/en-us/iaas/Content/API/SDKDocs/pythonsdk.htm) offers more flexibility but the API may seem complex at first.
This project is a practical example of how to use the SDK for managing compute instances.

# Prerequisites

1. A computer running Linux, macOS or Windows.
1. Python version [supported by the SDK](https://oracle-cloud-infrastructure-python-sdk.readthedocs.io/en/latest/#oracle-cloud-infrastructure-python-sdk-ocisdkversion).
1. [OCI CLI](https://docs.cloud.oracle.com/iaas/Content/API/SDKDocs/cliinstall.htm) is not required, but will make your setup easier.
1. A clone of this repository.

# Installation

## Virtual environment

The preferred way of installing the `oci-compute` package is to install it in a [Python virtual environment](https://docs.python.org/3/tutorial/venv.html):

```shell
# Clone the repository
git clone https://github.com/oracle/ol-sample-scripts.git
cd ol-sample-script/oci-compute
# Create and activate the virtualenv
python3 -m venv venv
source venv/bin/activate
# Install the package
pip3 install .
# Package will be installed as venv/bin/oci-compute
./venv/bin/oci-compute --version
```

You don't have _activate_ the virtual environment to run `oci-compute`.

## User level / system wide install

Alternatively you can install the package at user level or system wide. The latter is strongly discouraged as it can potentially update system libraries.

For a user level installation:

```shell
# Clone the repository
git clone https://github.com/oracle/ol-sample-scripts.git
cd ol-sample-script/oci-compute
# Install the package
pip3 install .
# Package will be installed in the user install directory for your platform. Typically ~/.local/
~/.local/bin/oci-compute --version
```

# Configuration

## SDK configuration

To access your OCI environment you need to provide access Keys and OCIDs. The required configuration files are described in [Tools Configuration](https://docs.cloud.oracle.com/en-us/iaas/Content/ToolsConfig.htm).

The easiest way to have your environment properly configured is to install the [OCI CLI](https://docs.cloud.oracle.com/iaas/Content/API/SDKDocs/cliinstall.htm) and run:

```shell
oci setup config
```

## oci-compute configuration

The `oci-compute` script is using an _rc file_ the same way the OCI CLI does. The default configuration file name is `~/.oci/oci_compute_rc`. See [Configuring the CLI](https://docs.cloud.oracle.com/en-us/iaas/Content/API/SDKDocs/cliconfigure.htm) for more information about syntax, sections and inheritance.

`oci-compute` command line options will source their default values from the _rc file_.

_Rc file_ example:

```
[DEFAULT]
# Global defaults for oci-compute
compartment-id = ocid1.compartment.oc1..xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
shape = VM.Standard2.1
availability-domain = ad-3
vcn-name = MyVCN
ssh-authorized-keys-file = ~/.ssh/id_rsa.pub

[FREE_TIER]
# Overrides defaults for the free tier tenancy
compartment-id = ocid1.tenancy.oc1..yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy
shape = VM.Standard.E2.1.Micro
availability-domain = ad-1
vcn-name = VCN-Free

[DEVEL]
# Overrides for development images
market-image-name = Oracle Cloud Developer Image
shape = VM.Standard2.4
availability-domain = ad-2
```

Note that the sections must also exist in the `~/.oci/config` configuration file (they can be empty as they will inherit their defaults from the `DEFAULT` section).

# Usage

The script support the `instance`, `list` and `provision` commands:

```
$ oci-compute --help
Usage: oci-compute [OPTIONS] COMMAND [ARGS]...

  Provision Oracle Cloud Infrastructure compute instances through the Python
  SDK.

Options:
  --version           Show the version and exit.
  -v, --verbose       Verbose mode
  --config-file PATH  The path to the config file.  [default: ~/.oci/config]
  --profile TEXT      The profile in the config file to load.  [default:
                      DEFAULT]

  --rc-file PATH      The path to the OCI Provision specific configuration
                      file  [default: ~/.oci/oci_compute_rc]

  --help              Show this message and exit.

Commands:
  instance   Manage compute instances.
  list       List available images.
  provision  Provision instance.

```

You can list/provision images from the following three sources:
- Platform Images: pre-built images for Oracle Cloud Infrastructure.
- Custom images: images created or imported into your Oracle Cloud Infrastructure environment.
- Marketplace Images: pre-built Oracle enterprise images and solutions as well as Trusted third-party images published by Oracle partners.  
  For the Marketplace images:
  - you will need to review and accept the terms of use for the image the first time you provision it.
  - the script will only list/provision free of charge images.

```
$ oci-compute list --help
Usage: oci-compute list [OPTIONS] COMMAND [ARGS]...

  List available images.

Options:
  --help  Show this message and exit.

Commands:
  custom    List Custom Images
  market    List free Marketplace Images
  platform  List Platform Images
```

The `provision` command accepts a `--cloud-init-file` parameter which will be run at instance provisioning.

The `instance` command allows you to list, start, shutdown and terminate instances:
```
$ oci-compute instance --help
Usage: oci-compute instance [OPTIONS] COMMAND [ARGS]...

  Manage compute instances.

Options:
  --help  Show this message and exit.

Commands:
list       List compute instances
shutdown   Shutdown compute instances
start      Start compute instances
terminate  Terminate compute instances

```

# Sample session
```
$ oci-compute -v provision market --image-name 'Cloud Devel' --display-name dev --cloud-init-file ~/bin/oci-cloudinit.sh
+++ oci-compute: Retrieving Marketplace listing
    oci-compute: Publisher                : Oracle
    oci-compute: Image                    : Oracle Cloud Developer Image
    oci-compute: Description              : An Oracle Linux 7-based image with the latest development tools, languages, Oracle Cloud Infrastructure Software Development Kits and Database connectors at your fingertips
+++ oci-compute: Retrieving listing details
    oci-compute: Latest version           : Oracle Cloud Developer Image 19.11
    oci-compute: Released                 : 2019-11-21 00:00:00+00:00
+++ oci-compute: Checking agreements acceptance
    oci-compute: This image is subject to the following agreement(s):
    oci-compute: - I have reviewed and accept the <link>Oracle Standard Terms and Restrictions</link>
    oci-compute:   Link: https://cloudmarketplace.oracle.com/marketplace/content?contentId=18088784&render=inline
I have reviewed and accept the above agreement(s) [y/N]: y
    oci-compute: Accepting agreement(s)
+++ oci-compute: Checking Application Catalog subscription
    oci-compute: Already subscribed
+++ oci-compute: Image selected:
    oci-compute: Name                     : OL Developer Image 19.11
    oci-compute: Created                  : 2019-11-19 22:03:55.214000+00:00
    oci-compute: Operating System         : Custom
    oci-compute: Operating System version : Custom
+++ oci-compute: Retrieving Availability Domain
    oci-compute: Name                     : awqR:eu-amsterdam-1-AD-1
+++ oci-compute: Retrieving VCN
    oci-compute: Name                     : MyVCN
+++ oci-compute: Retrieving subnet
    oci-compute: Subnet                   : Public Subnet
+++ oci-compute: Creating and launching instance
    oci-compute: Name                     : dev
    oci-compute: State                    : RUNNING
    oci-compute: Time created             : 2020-03-23 10:12:44.617000+00:00
+++ oci-compute: Retrieving VNIC attachments
    oci-compute: NIC attached - Index     : 0
+++ oci-compute: Retrieving VNIC data
    oci-compute: Private IP               : 10.0.0.13
    oci-compute: Public IP                : xxx.xxx.xxx.xxx
+Instance provisioned----------+
| Private IP | 10.0.0.13       |
| Public IP  | xxx.xxx.xxx.xxx |
+------------+-----------------+
$ ssh opc@xxx.xxx.xxx.xxx
Last login: Mon Mar 23 10:15:11 2020
[opc@dev ~]$ exit
logout
Connection to xxx.xxx.xxx.xxx closed.
$ oci-compute instance list
+Compute Instances---+-------------------------+---------+------------+-----------------+
| Name        | AD   | Time Created            | State   | Private IP | Public IP       |
+-------------+------+-------------------------+---------+------------+-----------------+
| dev         | AD-1 | 2020-03-23 10:12:44 UTC | Running | 10.0.0.13  | xxx.xxx.xxx.xxx |
+-------------+------+-------------------------+---------+------------+-----------------+
$ oci-compute instance terminate --display-name dev
+Instance: dev-------------------------+
| Created    | 2020-03-23 10:12:44 UTC |
| Private IP | 10.0.0.13               |
| Public IP  | 1xxx.xxx.xxx.xxx        |
+------------+-------------------------+
Terminate this instance [y/N]: y
Termination requested
$
```
