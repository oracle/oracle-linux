# Oracle Linux image tools

## Description

This repository provides tools to build Oracle Linux images for cloud deployment.

__Note__: as of March 2024 the scripts have been refactored and introduce breaking changes. See [CHANGELOG](CHANGELOG.md) for details.

The tools are architected around _distribution flavours_ and _target clouds_.
They currently support:

- Distributions:
  - Oracle Linux 7 update 9 -- Slim (x86_64 only)
  - Oracle Linux 8 update 9 -- Slim (x86_64 and aarch64)
  - Oracle Linux 9 update 3 -- Slim (x86_64 and aarch64)
- Clouds:
  - Microsoft Azure cloud (x86_64)  
    Target packages: WALinuxAgent  
    Image format: VHD
  - Oracle Cloud Infrastructure (OCI) (x86_64 and aarch64)  
    Target packages: qemu-guest-agent / cloud-init  
    Image format: QCOW2  
    __Note__: no specific OCI tools are actually installed; this image can be used in any cloud-init based environment.
  - Oracle Linux Virtualization Manager (OLVM) (x86_64)  
    Target packages: qemu-guest-agent / cloud-init  
    Image format: OLVM OVA
  - Oracle VM Server (OVM) (x86_64)  
    Target packages: oracle-template-config + vmapi  
    Image format: OVM OVA
  - Vagrant (VirtualBox provider) (x86_64)  
    Target packages: VirtualBox guest additions  
    Image format: box
  - Vagrant (libvirt provider) (x86_64)  
    Target packages: nfs-utils  
    Image format: box
  - UTM ([UTM for macOS](https://mac.getutm.app/)) (aarch64)  
    Target packages: none  
    Image format: utm  
    __Note__: only for aarch64 distributions
  - Generic (No cloud setup) (x86_64 and aarch64)  
    Target packages: none  
    Image format: VirtualBox OVA or QCOW2 (depending on the builder used)

## Requirements

### Overview

The tools require a Linux host supporting [KVM](https://linux-kvm.org) virtualization with the following installed:

- [`qemu-kvm`](http://www.qemu.org/) (Including `qemu-img`)
- [`libvirt`](https://libvirt.org/)
- [`virt-install`](https://virt-manager.org/)
- [`libguestfs`](https://libguestfs.org/) (including tools)

Additionally:

- the host architecture must match the architecture of the target image (e.g.: an `aarch64` host is needed to build `aarch64` images)
- the host kernel must support the filesystem used in the guest (e.g.: the host kernel must support `btrfs` to build an image with a `btrfs` filesystem)

For building [HashiCorp Vagrant](https://vagrantup.com/) boxes for the libvirt provider, download the [`create_box.sh`](https://github.com/vagrant-libvirt/vagrant-libvirt/blob/master/tools/create_box.sh) third party script from the [`vagrant-libvirt`](https://github.com/vagrant-libvirt/vagrant-libvirt) project or install [Vagrant](https://vagrantup.com/) and the [`vagrant-libvirt`](https://github.com/vagrant-libvirt/vagrant-libvirt) plugin.

### Oracle Linux 8

```shell
dnf module install virt
dnf install qemu-img libguestfs-tools virt-install
dnf install zip  # For UTM images
```

### Oracle Linux 9

```shell
dnf install libvirt qemu-kvm libguestfs
dnf install qemu-img guestfs-tools virt-install
dnf install zip  # For UTM images
```

## Build instructions

The image builder does not require system privileges and should not be run as root.

1. Clone this repo:

   ```shell
   git clone https://github.com/oracle/oracle-linux.git
   ```

1. Set up a separate workspace directory where the image will be built.
  Ensure there is enough free space in the workspace partition, the builder will need up the two times the image size.
1. Configure your build environment in the `env.properties` file (or in a copy).  
  Minimal configuration:
    - `WORKSPACE`: path of your workspace directory
    - `ISO_URL`: location of the Oracle Linux distribution ISO
    - `ISO_CHECKSUM`: checksum for the ISO file  
      Checksums files are available on the [Verify Oracle Linux Downloads](https://linux.oracle.com/security/gpg/) page
    - `CLOUD`: cloud target (azure, oci, olvm, ovm, utm, vagrant-libvirt, vagrant-virtualbox or none)
1. Run the builder as a non-privileged user:

   ```shell
   ./bin/build-image.sh --env ENV_PROPERTY_FILE`
   ```

## Advanced configuration

### Using _boot_ ISO images

Instead of providing an Oracle Linux distribution ISO you can use a _boot_ ISO image.
In that case, you will have to provide an URL to an installation tree and optionally additional yum repositories required by the installation.

Example for an Oracle Linux 9 using the UEK boot ISO:

```Shell
ISO_URL="https://yum.oracle.com/ISOS/OracleLinux/OL9/u4/x86_64/OracleLinux-R9-U4-x86_64-boot-uek.iso"
REPO_URL="https://yum.oracle.com/repo/OracleLinux/OL9/baseos/latest/x86_64"
REPO[AppStream]="https://yum.oracle.com/repo/OracleLinux/OL9/appstream/x86_64"
REPO[ol9_UEKR7]="https://yum.oracle.com/repo/OracleLinux/OL9/UEKR7/x86_64"
```

### Customizing builds

The build tool can be used to create custom images based on the existing Distributions and Clouds.

Custom image definitions must reside in a subdirectory of the `custom` directory (use a symbolic link if you want to keep your project separate).

A typical use case is installing additional packages.
You only need to provide a `provision.sh` file with a `custom::provision()` bash function which will be invoked from inside the VM.

For more complex use cases, hooks are available at all stages of the build; for more details see the sample project`template` in the `custom` directory.

Specific actions can be executed depending on the selected Distribution and Cloud by testing the `DISTR` and `CLOUD` environment variables.

### Configuration files

For a given Oracle Linux distribution and target Cloud, the following properties are taken in consideration:

- Global `env.properties.default` file
- Distribution `env.properties` file
- Cloud `env.properties` file
- Cloud distribution specific `env.properties` file
- Custom `env.properties` file
- Local `env.properties` file (passed as parameter to the builder)

Files are processed in that order.  
Changes should be made to the local env.properties file which will override any definition made in an upstream property file.  
Relevant parameters are documented in the distributed [`env.properties`](env.properties) sample file.

![File layout and process](images/olit.png)

## Cloud specific notes

### OCI

The Oracle Cloud Infrastructure `oci` cloud target generates an `QCOW2` file which can be uploaded in an _Object Storage_ bucket and imported as _Custom Image_.
This can be done from the Console, or using the [Command Line Interface (CLI)](https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/cliconcepts.htm). E.g.:

```shell
# Upload in the Object Storage Bucket
oci os object put -bn my_bucket \
  --file /workspace/OL7U9_x86_64-oci-b0/OL7U9_x86_64-oci-b0.qcow2
# Import as Custom image
oci compute image import from-object -bn my_bucket \
  --namespace my_namespace \
  --name OL7U9_x86_64-oci-b0.qcow2 \
  --display-name MyImage \
  --launch-mode PARAVIRTUALIZED \
  --source-image-type QCOW2
# Import might take some time, you can monitor the progress with:
oci compute image get \
  --image-id my_image_ocid \
  --query 'data."lifecycle-state"'
# or
oci work-requests work-request get \
  --work-request-id my_work_request_ocid \
  --query 'data."percent-complete"'
# my_image_ocid and my_work_request_ocid OCIDs are returned  by the import command
```

### OLVM

The `olvm` cloud target generates an OVA file. The process to import OVA files in the Oracle Linux Virtualization Manager is described in this [blog post](https://blogs.oracle.com/scoter/import-configure-oracle-linux-7-template-for-oracle-linux-kvm).

For cloud-init support, you will need to specify `CLOUD_INIT="Yes"` in your `env.properties` file.

## Builder architecture

### Directory structure

The `build-image` script relies on the following directory structure:

- distr: directory for all Oracle Linux distributions
  - _distribution name_
    - env.properties: distribution parameters
    - _name_-ks.cfg: kickstart file for the distribution
    - provision.sh: provisioning script which is run in the VM after installation
    - image-scripts: parameter validation, kickstart customisation and image cleanup scripts run on the host
    - files (directory): all files in this directory will be copied in the VM during provisioning
- cloud: directory for all target clouds
  - _cloud name_
    - env.properties: cloud parameters
    - provision.sh: provisioning script which is run in the VM after installation
    - image-scripts: parameter validation and image cleanup and packaging scripts run on the host
    - files (directory): all files in this directory will be copied in the VM during provisioning
    - _distribution name_: in case a a distribution specific action needs to be done for this cloud target, it can be defined in this directory.

Most of the files are optional, only define what is needed.

### Build process

The builder will process the directories in the following order:

1. Read properties files as described in [advanced configuration](#advanced-configuration).  
  The properties are available in all scripts, on the host and in the VM during provisioning.  
  Properties can be validated at distribution / cloud level:
    - distr::validate
    - cloud::validate
    - cloud_distr::validate
    - custom::validate
1. Select a kickstart file from _distr_ and customise it. The following hooks are called if defined:
    - distr::kickstart
    - cloud_distr::kickstart
    - custom::kickstart
1. Stage files from the _files_ directories. These files are copied during provisioning in `PROVISION_DIR` in the VM.
1. Run `virt-install` to create the image as described in the kickstart file.
1. Run `virt-customize` to actually provision the image.  
   The optional `::customize_args` hooks in the `image_scripts.sh` files are invoked to provide additional arguments to `virt-customize`.  
   The `provision.sh` scripts run in the following order:
    - distr::provision
    - cloud::provision
    - cloud_distr::provision
    - custom::provision
    - custom::cleanup
    - cloud_distr::cleanup
    - cloud::cleanup
    - distr::cleanup
1. Run `virt-sysprep` to _seal_ the image (final cleanup).  
   The optional `::sysprep_args` hooks in the `image_scripts.sh` files are invoked to provide additional arguments to `virt-sysprep`.  
1. Image packaging: the generated image is packaged in its final format.
  Only the first script found is executed:
    - custom::image_package
    - cloud_distr::image_package
    - cloud::image_package

## Feedback

Please provide feedback of any kind via GitHub issues on this repository.

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md) for details.
