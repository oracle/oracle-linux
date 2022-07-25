# Oracle Linux image tools

## Description

This repository provides tools to build Oracle Linux images for cloud deployment.

The images built by these tools are based on distribution flavours and target packages.
Image building is accomplished using Packer to build images from the Oracle Linux ISO using Oracle VM VirtualBox or QEMU/KVM builders.

The tool currently supports:

- Distributions:
  - Oracle Linux 7 update 9 -- Slim (x86_64)
  - Oracle Linux 8 update 6 -- Slim (x86_64 and aarch64)  
    __Note__: for aarch64, only Generic and OCI clouds are supported
  - Oracle Linux 9 update 0 -- Slim (x86_64 and aarch64)  
    __Note__: for aarch64, only Generic and OCI clouds are supported
- Clouds:
  - Microsoft Azure cloud  
    Target packages: WALinuxAgent  
    Image format: VHD
  - Oracle Cloud Infrastructure (OCI)  
    Target packages: qemu-guest-agent / cloud-init  
    Image format: QCOW2  
    __Note__: no specific OCI tools are actually installed; this image can be used in any cloud-init based environment.
  - Oracle Linux Virtualization Manager (OLVM)  
    Target packages: qemu-guest-agent / cloud-init  
    Image format: OLVM OVA
  - Oracle VM Server (OVM)  
    Target packages: oracle-template-config + vmapi  
    Image format: OVM OVA
  - Vagrant (VirtualBox provider - requires VirtualBox for the build)  
    Target packages: VirtualBox guest additions  
    Image format: box
  - Vagrant (libvirt provider)  
    Target packages: nfs-utils  
    Image format: box
  - Generic (No cloud setup)  
    Target packages: none  
    Image format: VirtualBox OVA or QCOW2 (depending on the builder used)

Additional information is available in the [Building (Small) Oracle Linux Images For The Cloud](https://blogs.oracle.com/linux/post/building-small-oracle-linux-images-for-the-cloud) blog post.

## Build instructions

The build script requires a Linux environment and has been tested on Oracle Linux 7 and 8.

1. Install either QEMU or VirtualBox (VirtualBox required for Vagrant VirtualBox images):
   - Oracle Linux 7:  
     `yum --enablerepo=ol7_kvm_utils group install "Virtualization Host"`  
     or  
     `yum --enablerepo=ol7_developer install VirtualBox-6.1`
   - Oracle Linux 8:  
     `dnf module install virt`  
     or  
     `dnf --enablerepo=ol8_developer install VirtualBox-6.1`
1. Install `kpartx` and `qemu-img` to manipulate the artifacts
   - Oracle Linux 7:  
     `yum --enablerepo=ol7_kvm_utils install kpartx qemu-img`
   - Oracle Linux 8:  
     `dnf install kpartx qemu-img`
1. Install packer:  
   - Oracle Linux 7:  
     `yum --enablerepo=ol7_developer install packer`
   - Oracle Linux 8: Download and install Packer from [HashiCorp](https://www.packer.io/downloads/)
1. Cloud specific requirements:
   - For `Vagrant` box (VirtualBox provider), install [HashiCorp Vagrant](https://vagrantup.com/)
   - For `Vagrant` box (libvirt provider), download the [`create_box.sh`](https://github.com/vagrant-libvirt/vagrant-libvirt/blob/master/tools/create_box.sh) third party script from the [`vagrant-libvirt`](https://github.com/vagrant-libvirt/vagrant-libvirt) project or install [HashiCorp Vagrant](https://vagrantup.com/) and the [`vagrant-libvirt`](https://github.com/vagrant-libvirt/vagrant-libvirt) plugin
1. Clone this repo:  
  `git clone https://github.com/oracle/oracle-linux.git`
1. The build script need root privileges during the build.
  Ensure `sudo` is properly configured for your build user
1. Set up a separate workspace directory where the image will be built.
  Ensure there is enough free space in the workspace partition, the builder will need up the two times the image size.
1. Configure your build environment in the `env.properties` file (or in a copy).  
  Minimal configuration:
    - `WORKSPACE`: path of your workspace directory
    - `ISO_URL`: location of the Oracle Linux distribution ISO
    - `ISO_CHECKSUM`: checksum for the ISO file. As from packer 1.6.0, you can prepend the checksum type (see [packer documentation](https://www.packer.io/docs/builders/virtualbox/iso#iso_checksum))
    - `CLOUD`: cloud target (azure, oci, olvm, ovm or none)
    - `PACKER_BUILDER`: builder used by packer (virtualbox-iso.x86-64 or qemu.x86-64)
1. Run the builder:  
  `./bin/build-image.sh --env ENV_PROPERTY_FILE`

## Advanced configuration

### Using _boot_ ISO images

Instead of providing an Oracle Linux distribution ISO you can use a _boot_ ISO image.
In that case, you will have to provide an URL to an installation tree and optionally additional yum repositories required by the installation.

Example for an Oracle Linux 9 using the UEK boot ISO:

```Shell
ISO_URL="https://yum.oracle.com/ISOS/OracleLinux/OL9/u0/x86_64/OracleLinux-R9-U0-x86_64-boot-uek.iso"
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
Changes should be made to a local env.properties file which can override any definition made in an upstream property file.  
Relevant parameters are documented in the distributed [`env.properties`](env.properties) file.

## Cloud specific notes

### OCI

The Oracle Cloud Infrastructure `oci` cloud target generates an `QCOW2` file which can be uploaded in an _Object Storage_ bucket and imported as _Custom Image_.
This can be done from the Console, or using the [Command Line Interface (CLI)](https://docs.cloud.oracle.com/en-us/iaas/Content/API/Concepts/cliconcepts.htm). E.g.:

```shell
# Upload in the Object Storage Bucket
oci os object put -bn my_bucket \
  --file /workspace/OL7U9_x86_64-oci-b0/OL7U9_x86_64-oci-b0.qcow
# Import as Custom image
oci compute image import from-object -bn my_bucket \
  --namespace my_namespace \
  --name OL7U9_x86_64-oci-b0.qcow \
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

- distr: directory for all Oracle Linux distribution
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
1. Select a packer configuration file and customise it. The following hooks are called if defined:
    - distr::packer_conf
    - cloud_distr::packer_conf
    - custom::packer_conf
1. Stage files from the _files_ directories. These files are copied during provisioning in `/tmp/packer_files` in the VM.
1. Run packer to provision the VM image.
  During provisioning the `provision.sh` scripts run in the following order:
    - distr::provision
    - cloud::provision
    - cloud_distr::provision
    - custom::provision
    - custom::cleanup
    - cloud_distr::cleanup
    - cloud::cleanup
    - distr::cleanup
    - distr::seal[^1]
1. Image cleanup: the generated image is mounted on the host and the `image-scripts` scripts are run[^1]:
    - custom::cleanup
    - cloud_distr::cleanup
    - cloud::cleanup
    - distr::cleanup
1. Image packaging: the generated image is packaged in its final format.
  Only the first script found is executed:
    - custom::image_package
    - cloud_distr::image_package
    - cloud::image_package

[^1]: `provision` `seal` vs. `image-scripts` `cleanup`.
These functions have the same purpose: _seal_ the image before packaging.
The difference is that the former runs in the VM while the latter runs on the host.
Sealing on the host might be more efficient, but when it is not possible to mount the image disk on the host, in-VM sealing can be used. When no `image-scripts` `cleanup` are defined, no attempt will be made to mount the filesystem on the host.

## Feedback

Please provide feedback of any kind via GitHub issues on this repository.

## Contributing

See [CONTRIBUTING](CONTRIBUTING.md) for details.
