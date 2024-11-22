# Release Notes

## November 2024

### New Features

- Update for OL9.5

### Bug fixes

- Fix regression for Vagrant Virtualbox boxes (set default NIC type to `virtio`)

## September 2024

### Bug fixes

- Use a version-based sort on the output of osinfo-query to ensure we always use the latest available variant on the build host when creating the initial VM

## May 2024

### New Features

- OL 8.10 & OL9.4 update

### Bug fixes

- Truncate `/etc/resolv.conf` in cleanup
- Pin `kernel-uek-core` to prevent accidental removal

## March 30, 2024

### Bug fixes

- `cloud-init collect-logs` requires `tar`

## March, 2024

Major refactoring of the scripts, reducing dependencies on third parties.
The build tools mainly rely on  [`qemu-kvm`](http://www.qemu.org/), using [`libvirt`](https://libvirt.org/) and [`libguestfs`](https://libguestfs.org/).

As it is a breaking change, previous version has been archived under the `olit-legacy` branch (unmaintained).

### Refactor

The overall build process has been changed. In previous releases we had:

1. Create image from distribution ISO and a kickstart file
1. Customize the image by running provision scripts inside the running VM
1. Cleanup the environment by mounting the image filesystems on the host;
   the outcome is a raw disk image
1. Package the image for the target cloud

As of this release, we have:

1. Create image: unchanged
1. Use [`virt-customize`](customize) to run the provisioning scripts
1. Use [`virt-sysprep`](https://libguestfs.org/virt-sysprep.1.html)/[`virt-sparsify`](https://libguestfs.org/virt-sparsify.1.html) for the cleanup;
   the outcome is a compressed qcow2 image
1. Package image: unchanged

Notable code changes:

- Drop support for [VirtualBox](https://www.virtualbox.org/) as **builder** (you can still create Vagrant VirtualBox **images**)
- `image-scripts.sh` `::seal()` functions obsolete; code moved to `provision.sh` `::cleanup()` functions.
  We don't need anymore a separate _offline_ cleanup as `virt-customize` doesn't actually run the built VM.
- Simplify `provision.sh` `::cleanup()` functions as most parts are now handled by `virt-sysprep` operations.
- Add `image-scripts.sh` `::customize_args()` and  `::sysprep_args()` hooks to inject command line parameters for  `virt-customize` and `virt-sysprep`.
- Root privileges are no longer required on the build host.
- Root access to the image VM is no longer needed at built time. Root password and/or ssh public key can still be set for the image; parameters have been renamed to ensure configuration is secure by default.
- Move common code to the `common.sh` and `provision-common.sh` libraries.
- QCOW2 image files now have the `qcow2` extension instead of `qcow`.

### Configuration variables

Changes to the configuration variables.
See the corresponding `env.properties` files for more details.

New variables

- Generic
  - `INSTALL_WAIT_TIME`: configurable timeout for initial image creation
  - `OS_VARIANT` (optional): OS variant used when creating the image
  - `BOOT_MODE`: OS boot mode (`bios` or `efi`)
  - `BOOT_COMMAND_SERIAL_CONSOLE`: kernel parameters to enable serial console
  - `BOOT_LOCATION`(optional): kernel and initrd location on the distribution media
  - `ROOT_PASSWORD` (optional, default: locked): password for the root account in the generated image
  - `ROOT_SSH_KEY` (optional): public ssh key the root account in the generated image
  - `PERMIT_ROOT_LOGIN` (Default: prohibit-password): default policy for ssh root login
  - `CACHE_DIR` (Default: `.cache` in workspace directory): location of ISO images cache
- utm cloud
  - `OPC_PASSWORD`: password for the `opc` user for UTM builds

Changed variables

- `DISTR`: is now mandatory
- `ISO_LABEL`: is now optional
- `BOOT_COMMAND`: array of kernel parameters instead of a string

Obsolete variables

- `LOCK_ROOT`, `SSH_KEY_FILE`, `SSH_PASSWORD`: root access to the image is not needed anymore, see new `ROOT_PASSWORD`, `ROOT_SSH_KEY` if root access to the generated image is needed
- `X2APIC`
- `PACKER`, `PACKER_BUILD_OPTIONS`, `PACKER_BUILDER`
- `QEMU_BINARY`

### New features

- sshd `PermitRootLogin` parameter is now `prohibit-password` by default for all images (instead of `yes` for OL7/OL8)
- update azure cloud for OL9

### Bug fixes

- Wrong pattern matching in bash regular expressions when validating variables
- TERM variable in serial console configuration for OVM not escaped properly
- Wrong swap page size for aarch64 builds when host is running UEK6 kernel
- Workaround for OL8 cloud-init issue in OCI
- Setup OCI yum mirrors for OCI images

### Documentation

README file updated
