oci-provision
=============

A simple `bash` script to provision cloud instances on [Oracle Cloud Infrastructure](https://www.oracle.com/cloud/) (OCI).

# About
Oracle provides a command line interface for Oracle Cloud Infrastructure ([GitHub](https://github.com/oracle/oci-cli) / [Documentation](https://docs.cloud.oracle.com/iaas/Content/API/Concepts/cliconcepts.htm)).
It is quite convenient when you want to quickly create instances in a reproducible way without going the BUI.

This small project illustrates usage of the OCI CLI to create instances from the _Platform_ catalog or the _Marketplace_.

# Prerequisites
1. A computer running Linux, macOS or Windows.\
   Windows users will need a `bash` shell either from the [Windows Subsystem for Linux](https://docs.microsoft.com/en-us/windows/wsl/about) or [Git BASH](https://gitforwindows.org/).
1. [OCI CLI](https://docs.cloud.oracle.com/iaas/Content/API/SDKDocs/cliinstall.htm) installed and configured.

# Background information
## Process overview
The overall flow of the script is straightforward:
1. Search for the requested image.
1. Launch an instance and wait until it is ready.
1. Retrieve the instance Public IP

The first step depends on the image type used: Platform or Marketplace images.

## Platform images
This is the simple case: you need to provide:
- The operating system (e.g.: _Oracle Linux_)
- The version of the operating system (e.g.: _7.7_)

The script will then find latest available version of the image.

You can list available images with:
```
oci compute image list \
  --query 'data [*].{OS: "operating-system", Version:"operating-system-version"}' \
  --output table |
  awk '
    BEGIN   { uniq = "sort -u" }
    NR == 1 { hdr = $0 }
    NR < 4  { print; next }
    /^\|/   { print | uniq }
    END     { close(uniq); print hdr}
  '
```

## Marketplace images
This case is a bit more convoluted: Marketplace images require you to accept the _Oracle Standard Terms and Restrictions_ to be able to install these.  
Fortunately, this can also be done through the OCI CLI using the [Partner Image Catalog](https://docs.cloud.oracle.com/iaas/tools/oci-cli/2.6.15/oci_cli_docs/cmdref/compute/pic.html) (pic) commands.

The flow for the Marketplace images is:
- Search and retrieve image list from the catalog.
- Find the latest image version compatible with the selected shape.
- Retrieve the _agreement_ needed to use this shape.
- _Subscribe_ to this agreement

# Getting started
The main purpose of this script is to easily create instances in a configured tenancy. That is:
- in a specific compartment;
- attached to an existing _Virtual Cloud Network_ (VCN) and _Subnet_.

The script assumes that the OCI CLI is installed and configured, and that you already have defined a default compartment in your oci cli rc file (`~/.oci/oci_cli_rc`). E.g.:
```
[DEFAULT]
compartment-id = ocid1.compartment.oc1..xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Before running `oci-provision.sh`:
- Clone this repository
- Copy the `oci-provision.env.distr` to `oci-provision.env`
- Edit `oci-provision.env`. The following entries are mandatory:
  - `public_key`: path to your SSH public key file (to connect to the instance)
  - `vcn_name`: name of an existing VCN
  - `subnet`: name of an existing subnet in that VCN

Usage:
```
Usage: oci-provision.sh OPTIONS

  Provision an OCI compute instance.

Options:
  --help, -h                show this text and exit
  --os                      operating system (default: Oracle Linux)
  --os-version              operating system version
  --image IMAGE             image search pattern in the Marketplace
                            os/os-version are ignored when image is specified
  --custom IMAGE            image search pattern for Custom images
                            os/os-version are ignored when custom is specified
  --name NAME               compute VM instance name
  --shape SHAPE             VM shape (default: VM.Standard2.1)
  --ad AD                   Availability Domain (default: AD-1)
  --key KEY                 public key to access the instance
  --vcn VCN                 name of the VCN to attach to the instance
  --subnet SUBNET           name of the subnet to attach to the instance
  --cloud-init CLOUD-INIT   optional clout-init file to provision the instance

Default values for parameters can be stored in ./oci-provision.env
```

# Examples
## Platform image
To instantiate a Platform Image, `os` and `os-version` must be provided:
```
$ ./oci-provision.sh --os "Oracle Linux" --os-version "7.7" --name ol77
+++ oci-provision.sh: Getting latest image for Oracle Linux 7.7
    oci-provision.sh: Retrieved: Oracle-Linux-7.7-2019.12.18-0
+++ oci-provision.sh: Retrieving AD name
+++ oci-provision.sh: Retrieving VCN
+++ oci-provision.sh: Retrieving subnet
+++ oci-provision.sh: Provisioning ol77 with VM.Standard2.1
Action completed. Waiting until the resource has entered state: ('RUNNING',)
+++ oci-provision.sh: Getting public IP address
    oci-provision.sh: Public IP is: xxx.xxx.xxx.xxx
```

## Marketplace image
The `image` parameter takes precedence over the `os` / `os-version` parameters and is a (case sensitive) search string for a Marketplace image.
If more than one image matches the string, the list of matching images is printed, otherwise the image is launched:
```
$ ./oci-provision.sh --image "Developer" --name devel
+++ oci-provision.sh: Getting image listing
    oci-provision.sh: Selected image:
    oci-provision.sh: Image      : Oracle Cloud Developer Image
    oci-provision.sh: Summary    : Oracle Cloud Developer Image
    oci-provision.sh: Description: An Oracle Linux 7-based image with the latest development tools, languages, Oracle Cloud Infrastructure Software Development Kits and Database connectors at your fingertips
+++ oci-provision.sh: Getting latest image version
    oci-provision.sh: Version Oracle_Cloud_Developer_Image_19.11 selected
+++ oci-provision.sh: Getting agreement and subscribing...
    oci-provision.sh: Term of use: https://objectstorage.us-ashburn-1.oraclecloud.com/n/partnerimagecatalog/b/eulas/o/oracle-apps-terms-of-use.txt
    oci-provision.sh: Subscribed
+++ oci-provision.sh: Retrieving AD name
+++ oci-provision.sh: Retrieving VCN
+++ oci-provision.sh: Retrieving subnet
+++ oci-provision.sh: Provisioning devel with VM.Standard2.1
Action completed. Waiting until the resource has entered state: ('RUNNING',)
+++ oci-provision.sh: Getting public IP address
    oci-provision.sh: Public IP is: xxx.xxx.xxx.xxx
```

## Custom image
The `custom` parameter takes precedence over the `os` / `os-version` parameters and is a (case sensitive) search string for a Custom image.
If more than one image matches the string, the list of matching images is printed, otherwise the image is launched:

```
$ ./oci-provision.sh --custom "OL7U7" --name ol7-custom
+++ oci-provision.sh: Getting custom image list for OL7U7
    oci-provision.sh: Selected image: OL7U7_x86_64-oci-b1
+++ oci-provision.sh: Retrieving AD name
+++ oci-provision.sh: Retrieving VCN
+++ oci-provision.sh: Retrieving subnet
+++ oci-provision.sh: Provisioning custom with VM.Standard2.1
Action completed. Waiting until the resource has entered state: ('RUNNING',)
+++ oci-provision.sh: Getting public IP address
    oci-provision.sh: Public IP is: xxx.xxx.xxx.xxx
```

# Cloud-init file
Additionally, a [Cloud-init](https://cloudinit.readthedocs.org/en/latest/topics/format.html) file can be specified to run custom scripts during instance configuration.
In its simplest format this file can be a shell script.\
The `oci-cloud-init.sh` script from this repo is provided as example:
```
$ ./oci-provision.sh --os "Oracle Linux" --os-version "7.7" --name ol77 --cloud-init oci-cloud-init.sh
```

Note that the provisioning script terminates when the instance is up and running, which is typically before cloud-init completes!
