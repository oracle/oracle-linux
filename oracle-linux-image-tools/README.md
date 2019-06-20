# Description
This repository provides tools to build Oracle Linux images for deployment in Microsoft Azure cloud and Oracle VM Server. 
The images built by these tools contain a minimal installation with a set of pre-installed packages and target packages. 
Image building is accomplished using Packer to build images from the Oracle Linux ISO using Oracle VM VirtualBox. 
Images built for Oracle VM Server are OVA format. Images for Azure are VHD format.

Target packages for Azure: WALinuxAgent

Target packages for OVM: oracle-template-config + vmapi

### Environment Properties

Setup env.properties file in your workspace directory with appropriate settings. A sample file can be found in the repo.

### Build instructions

1) Install packer and VirtualBox: `yum --enablerepo=ol7_developer install packer VirtualBox-6.0`

2) Clone this repo to the build system: `git clone https://github.com/oracle/ol-sample-scripts`

3) Set up a separate workspace directory where the image will be built. Export WORKSPACE environment variable with the workspace directory:

   `export WORKSPACE=/Image-build`

4) Copy Kickstart Config files `azure.cf` and `ol.cf` to a http server that is accessible from the build system.

5) OVM images require `mkovf`, which is provided by the `open-ovf` package on the Oracle VM Server ISO or from upstream.

6) Copy the Azure license file provided in the repo to a http server.

7) Build the image: `sh -x packer_builder.sh`

8) Image will copied to: `$WORKSPACE/vm_images`