# Creating an RPM package for your software

[RPM](https://en.wikipedia.org/wiki/RPM_Package_Manager) is both a
package manager and a file format (.rpm). It has been used by many Linux
distributions, including Oracle Linux, to ease the distribution,
installation and maintenance of software. In this document we\'ll
explain how to create an rpm using a simple example.

## Why create an RPM

Packaging software with RPM provides many advantages over delivering
software via a simple tarball. The main advantages are:

- Ease of installation
  - RPM can be installed, removed and upgraded in a consistent way
    by using package management tools such as Yum
- Ease of distribution
  - RPM files are self describing, they can contain information such
    as a description, installation instruction, list of files,
    dependencies version, etc.  \
    This helps users quickly understand what the software package is
    about, what version it is, what are its dependencies, how to
    install, etc.
  - RPMs can be added to repositories such as Yum (or in a software
    source via the OS Management service in [Oracle Cloud
    Infrastructure](https://www.oracle.com/cloud/) that allows users
    to find and install your software.
- Ease of integration
  - Linux distributions such as Oracle Linux use RPM to deliver
    software packages and keep track of what\'s installed in a
    central database. This avoids re-installation of an already
    installed software package and can also be used to determine
    which package installed files belong to.
- Ease of authentication
  - RPM can be signed using GPG to enable the user to verify the
    origin of a package.

## Overview

The main steps for packaging software are:

- Prepare your system to build an rpm
- Prepare your software for packaging
- Creating an RPM specification file (spec file)  
- Build the package using RPM
- Testing the newly built package

## Preparation

This step by step example can be run verbatim on an Oracle Linux 7
instance in [Oracle Cloud
Infrastructure](https://www.oracle.com/cloud/).

Install (as root) the rpm software needed to build rpms

    yum install rpmdevtools rpm-build rpm-sign

Generate the RPM tree structure in your home directory

    rpmdev-setuptree

The command creates the following directory tree:

    $ tree rpmbuild/
    rpmbuild/
    |-- BUILD
    |-- RPMS
    |-- SOURCES
    |-- SPECS
    `-- SRPMS

More information about the RPM packaging tools can be found in the [rpm
packaging
guide](https://rpm-packaging-guide.github.io/#rpm-packaging-tools).

TL;DR:  If you want to jump ahead and see how to generate an empty
package read the [Your First RPM Package
section](https://rpm-packaging-guide.github.io/#hello-world) from
the [rpm packaging
guide](https://rpm-packaging-guide.github.io/#rpm-packaging-tools).

## Software build and installation

RPMs original intended way of retrieving software source is via a
compressed source tarball specified as `Source*` tags in the spec file.
The [Maximum RPM](http://ftp.rpm.org/max-rpm/) book has a more
comprehensive [description](http://ftp.rpm.org/max-rpm/ch-rpm-build.html)
of this usage.  

In this page, for simplicity sake, instead of using an existing software
tarball we will create a simple test example.

This test example tarball can be generated running these commands:

    mkdir test-rpm-0.1
    echo "echo \"Hello World\"" > test-rpm-0.1/hello-world.sh
    echo "echo \"Bye Bye World\"" > test-rpm-0.1/bye-world.sh
    tar -czvf rpmbuild/SOURCES/test-rpm-0.1.tar.gz test-rpm-0.1/

Additional information on how to prepare different type of source code
can be found in the [Preparing Software for
Packaging](https://rpm-packaging-guide.github.io/#what-is-source-code) from
the [rpm packaging
guide](https://rpm-packaging-guide.github.io/#rpm-packaging-tools).

## Spec file creation

With the source software available in a compressed archive, we can now
start creating the RPM specification file. A spec file contains the
recipe that `rpmbuild` uses to generate the RPM.

Use the following command to generate a Skeleton specfile:

    rpmdev-newspec SPECS/test-rpm.spec

Below is a minimalistic spec file that can be used to
package test-rpm-0.1.tar.gz

As you can see a spec file contains a preamble and multiple sections.

The Preamble describes information about the package, it\'s name,
version, license, source location, etc.

The Requires keyword allow to state a dependency on other packages (here
bash). See the
[Dependencies](https://rpm.org/user_doc/dependencies.html) section of
[rpm.org](https://rpm.org/) for detailed information about the different
dependency keywords available.

The other sections describe the steps required to:

- prepare the software to be built (`%prep`)
- build the software from the source if needed (`%build`). It is not
  required with the current example.
- install the result of the software built on the operating system
  (`%install`)
- run any commands once the software is installed (`%post`). For
  example, It is useful to start a service once it\'s installed.

`%files` describes what files will be part of the package. It is possible
to specify the file permissions via `%defattr`

`%changelog` enables you to document the changes between versions of the RPM
package

The tag `?dist` in the release directive appends the distribution
shortname to the release number (test-rpm-0.1-**1.el7**.x86\_64.rpm)

    Name:           test-rpm
    Version:        0.1
    Release:        1%{?dist}
    Summary:        My test rpm
    License:        The Universal Permissive License (UPL), Version 1.0
    Source0:        test-rpm-0.1.tar.gz
    Requires:       bash

    %description
    A set of test scripts packaged in an RPM

    %prep
    %setup -q

    %build

    %install
    rm -rf $RPM_BUILD_ROOT
    install -d $RPM_BUILD_ROOT/opt/test-rpm
    install hello-world.sh $RPM_BUILD_ROOT/opt/test-rpm/hello-world.sh
    install bye-world.sh $RPM_BUILD_ROOT/opt/test-rpm/bye-world.sh

    %post
    chmod 755 -R /opt/test-rpm
    %files
    %dir /opt/test-rpm
    %defattr(-,root,root,-)
    /opt/test-rpm/hello-world.sh
    /opt/test-rpm/bye-world.sh

    %changelog
    * Mon Jul 6 2020 John Doe 
    - initial release

Comprehensive information about the spec file syntax can be found in the
[\'inside the spec file\'
section](http://ftp.rpm.org/max-rpm/ch-rpm-inside.html) of [Maximum
RPM](http://ftp.rpm.org/max-rpm/index.html) and in the [\'What is a SPEC
file\'
section](https://rpm-packaging-guide.github.io/#what-is-a-spec-file)
of the [rpm packaging
guide](https://rpm-packaging-guide.github.io/#rpm-packaging-tools).

## Building the RPM

With the software source archive and the spec file defined, now the RPM
can be built.

Use the rpmbuild command to build the rpm:

    $ rpmbuild -ba rpmbuild/SPECS/test-rpm.spec
    Executing(%prep): /bin/sh -e /var/tmp/rpm-tmp.oj3NLl
    + umask 022
    + cd /home/opc/rpmbuild/BUILD
    + cd /home/opc/rpmbuild/BUILD
    + rm -rf test-rpm-0.1
    + /usr/bin/gzip -dc /home/opc/rpmbuild/SOURCES/test-rpm-0.1.tar.gz
    + /usr/bin/tar -xf -
    + STATUS=0
    + '[' 0 -ne 0 ']'
    + cd test-rpm-0.1
    + /usr/bin/chmod -Rf a+rX,u+w,g-w,o-w .
    + exit 0
    Executing(%build): /bin/sh -e /var/tmp/rpm-tmp.9Qchsq
    + umask 022
    + cd /home/opc/rpmbuild/BUILD
    + cd test-rpm-0.1
    + exit 0
    Executing(%install): /bin/sh -e /var/tmp/rpm-tmp.JXpt9u
    + umask 022
    + cd /home/opc/rpmbuild/BUILD
    + '[' /home/opc/rpmbuild/BUILDROOT/test-rpm-0.1-1.el7.x86_64 '!=' / ']'
    + rm -rf /home/opc/rpmbuild/BUILDROOT/test-rpm-0.1-1.el7.x86_64
    ++ dirname /home/opc/rpmbuild/BUILDROOT/test-rpm-0.1-1.el7.x86_64
    + mkdir -p /home/opc/rpmbuild/BUILDROOT
    + mkdir /home/opc/rpmbuild/BUILDROOT/test-rpm-0.1-1.el7.x86_64
    + cd test-rpm-0.1
    + rm -rf /home/opc/rpmbuild/BUILDROOT/test-rpm-0.1-1.el7.x86_64
    + install -d /home/opc/rpmbuild/BUILDROOT/test-rpm-0.1-1.el7.x86_64/opt/test-rpm
    + install hello-world.sh /home/opc/rpmbuild/BUILDROOT/test-rpm-0.1-1.el7.x86_64/opt/test-rpm/hello-world.sh
    + install bye-world.sh /home/opc/rpmbuild/BUILDROOT/test-rpm-0.1-1.el7.x86_64/opt/test-rpm/bye-world.sh
    + /usr/lib/rpm/find-debuginfo.sh --strict-build-id -m --run-dwz --dwz-low-mem-die-limit 10000000 --dwz-max-die-limit 110000000 /home/opc/rpmbuild/BUILD/test-rpm-0.1
    /usr/lib/rpm/sepdebugcrcfix: Updated 0 CRC32s, 0 CRC32s did match.
    + '[' '%{buildarch}' = noarch ']'
    + QA_CHECK_RPATHS=1
    + case "${QA_CHECK_RPATHS:-}" in
    + /usr/lib/rpm/check-rpaths
    + /usr/lib/rpm/check-buildroot
    + /usr/lib/rpm/redhat/brp-compress
    + /usr/lib/rpm/redhat/brp-strip-static-archive /usr/bin/strip
    + /usr/lib/rpm/brp-python-bytecompile /usr/bin/python 1
    + /usr/lib/rpm/redhat/brp-python-hardlink
    + /usr/lib/rpm/redhat/brp-java-repack-jars
    Processing files: test-rpm-0.1-1.el7.x86_64
    Provides: test-rpm = 0.1-1.el7 test-rpm(x86-64) = 0.1-1.el7
    Requires(interp): /bin/sh
    Requires(rpmlib): rpmlib(CompressedFileNames) <= 3.0.4-1 rpmlib(FileDigests) <= 4.6.0-1 rpmlib(PayloadFilesHavePrefix) <= 4.0-1
    Requires(post): /bin/sh
    Processing files: test-rpm-debuginfo-0.1-1.el7.x86_64
    Provides: test-rpm-debuginfo = 0.1-1.el7 test-rpm-debuginfo(x86-64) = 0.1-1.el7
    Requires(rpmlib): rpmlib(FileDigests) <= 4.6.0-1 rpmlib(PayloadFilesHavePrefix) <= 4.0-1 rpmlib(CompressedFileNames) <= 3.0.4-1
    Checking for unpackaged file(s): /usr/lib/rpm/check-files /home/opc/rpmbuild/BUILDROOT/test-rpm-0.1-1.el7.x86_64
    Wrote: /home/opc/rpmbuild/SRPMS/test-rpm-0.1-1.el7.src.rpm
    Wrote: /home/opc/rpmbuild/RPMS/x86_64/test-rpm-0.1-1.el7.x86_64.rpm
    Wrote: /home/opc/rpmbuild/RPMS/x86_64/test-rpm-debuginfo-0.1-1.el7.x86_64.rpm
    Executing(%clean): /bin/sh -e /var/tmp/rpm-tmp.r3U4JO
    + umask 022
    + cd /home/opc/rpmbuild/BUILD
    + cd test-rpm-0.1
    + /usr/bin/rm -rf /home/opc/rpmbuild/BUILDROOT/test-rpm-0.1-1.el7.x86_64
    + exit 0

The resulting RPMs will be stored in  rpmbuild/SRPMS/ and rpmbuild/RPMS
subdirectories

## Signing the Package

Package signing allows the user to validate that the package has not
been tampered with after it was built.

There are multiple ways to sign a package.

### Checksum

The default option is using a checksum to ensure the file wasn\'t
corrupted during download.

To enable this checksum signing use the following to build your rpm

    rpmbuild -ba --sign rpmbuild/SPECS/test-rpm.spec

Signing can be validated by running

    $ rpm --checksig rpmbuild/RPMS/x86_64/test-rpm-0.1-1.el7.x86_64.rpm
    rpmbuild/RPMS/x86_64/test-rpm-0.1-1.el7.x86_64.rpm: sha1 md5 OK

If the RPM has been tampered with, the output will look like this

    $ rpm --checksig rpmbuild/RPMS/x86_64/test-rpm-0.1-1.el7.x86_64.rpm
    rpmbuild/RPMS/x86_64/test-rpm-0.1-1.el7.x86_64.rpm: SHA1 MD5 NOT OK

### GPG

If you want to cryptographically sign your RPM to ensure integrity with
GPG, you need to do the following:

- generate a key, using gpg. Here is an example for John Doe\
    Note to use a SHA256 digest, you need to add the following in
    \$HOME/.gnupg/gpg.conf:

        personal-digest-preferences SHA256
        cert-digest-algo SHA256
    &nbsp;

        $ gpg --gen-key
        gpg (GnuPG) 2.0.22; Copyright (C) 2013 Free Software Foundation, Inc.
        This is free software: you are free to change and redistribute it.
        There is NO WARRANTY, to the extent permitted by law.

        Please select what kind of key you want:
           (1) RSA and RSA (default)
           (2) DSA and Elgamal
           (3) DSA (sign only)
           (4) RSA (sign only)
        Your selection?
        RSA keys may be between 1024 and 4096 bits long.
        What keysize do you want? (2048)
        Requested keysize is 2048 bits
        Please specify how long the key should be valid.
                 0 = key does not expire
                = key expires in n days
              w = key expires in n weeks
              m = key expires in n months
              y = key expires in n years
        Key is valid for? (0)
        Key does not expire at all
        Is this correct? (y/N) y

        GnuPG needs to construct a user ID to identify your key.

        Real name: John Doe
        Email address: john.doe@example.com
        Comment:
        You selected this USER-ID:
            "John Doe "

        Change (N)ame, (C)omment, (E)mail or (O)kay/(Q)uit? O
        You need a Passphrase to protect your secret key.

        We need to generate a lot of random bytes. It is a good idea to perform
        some other action (type on the keyboard, move the mouse, utilize the
        disks) during the prime generation; this gives the random number
        generator a better chance to gain enough entropy.
        We need to generate a lot of random bytes. It is a good idea to perform
        some other action (type on the keyboard, move the mouse, utilize the
        disks) during the prime generation; this gives the random number
        generator a better chance to gain enough entropy.
        gpg: /home/opc/.gnupg/trustdb.gpg: trustdb created
        gpg: key D66B5435 marked as ultimately trusted
        public and secret key created and signed.

        gpg: checking the trustdb
        gpg: 3 marginal(s) needed, 1 complete(s) needed, PGP trust model
        gpg: depth: 0  valid:   1  signed:   0  trust: 0-, 0q, 0n, 0m, 0f, 1u
        pub   2048R/D66B5435 2020-07-08
              Key fingerprint = 503D 1738 114A BA5A 4F71  3304 72A1 1FEF D66B 5435
        uid                  John Doe 
        sub   2048R/6753905B 2020-07-08

- add the public key in the rpm database

        gpg --export -a 'John Doe' > test-gpg-key

    as root, run

        rpm --import test-gpg-key

    You can verify the key is added by running

        rpm -q gpg-pubkey --qf '%{name}-%{version}-%{release} --> %{summary}\n'

- Add the a gpg macro in the \$HOME/.rpmmacros

        $ more .rpmmacros
        %_gpg_name John Doe 

        %_topdir %(echo $HOME)/rpmbuild
        ...

- sign the package\
    \
    Either while building the rpm with

        rpmbuild -ba --sign rpmbuild/SPECS/test-rpm.spec

    or once the rpm is already built with

        rpm --addsign rpmbuild/RPMS/x86_64/test-rpm-0.1-1.el7.x86_64.rpm

- You can verify the signature with

        $ rpm --checksig rpmbuild/RPMS/x86_64/test-rpm-0.1-1.el7.x86_64.rpm
        rpmbuild/RPMS/x86_64/test-rpm-0.1-1.el7.x86_64.rpm: rsa sha1 (md5) pgp md5 OK

    compare to the checksum , you see pgp has been added.

    You can also check the signature field by running

        $ rpm -qpi rpmbuild/RPMS/x86_64/test-rpm-0.1-1.el7.x86_64.rpm
        Name        : test-rpm
        Version     : 0.1
        Release     : 1.el7
        Architecture: x86_64
        Install Date: (not installed)
        Group       : Unspecified
        Size        : 40
        License     : The Universal Permissive License (UPL), Version 1.0
        Signature   : RSA/SHA256, Wed Jul  8 18:06:15 2020, Key ID 72a11fefd66b5435
        Source RPM  : test-rpm-0.1-1.el7.src.rpm
        Build Date  : Wed Jul  8 18:06:13 2020
        Build Host  : test-rpm-build-erwannc.appad1iad.osdevelopmeniad.oraclevcn.com
        Relocations : (not relocatable)
        Summary     : My test rpm
        Description :
        A set of test scripts packaged in an RPM

More details about this topic can be found in the [\'Signing Packages\'
section](https://rpm-packaging-guide.github.io/#Signing-Packages)
of the [rpm packaging
guide](https://rpm-packaging-guide.github.io/#rpm-packaging-tools) and
the [\'Adding PGP Signatures to a Package\'
section](http://ftp.rpm.org/max-rpm/ch-rpm-pgp.html) of  [Maximum
RPM](http://ftp.rpm.org/max-rpm/) book.

## Testing

Once the package is built and signed, you can test it by running the
command as root

    $ rpm -ivh rpmbuild/RPMS/x86_64/test-rpm-0.1-1.el7.x86_64.rpm
    Preparing...                          ################################# [100%]
    Updating / installing...
       1:test-rpm-0.1-1.el7               ################################# [100%]

You can test its removal by running this command as root

    $ rpm -ev test-rpm
    Preparing packages...
    test-rpm-0.1-1.el7.x86_64

## Stable build environment

Once the initial package has been built, it is important to create a
build environment that can reliably create your rpm without the risk of
external changes affecting the package generation.

There are two main ways of achieving this:

- Create a container to build the rpm, this gives complete control
    over the build environment and ensure no extra packages is installed
    by mistake. Many rpm builder docker image examples can be found to
    get started.
- If using a containers isn\'t a viable option, you can
    use [Mock](https://github.com/rpm-software-management/mock/wiki),
    which is a tool to create a chroot environment (a kind of
    encapsulated file system) to build packages

## Publishing

Now that your RPM is ready, you can publish it in a yum repository or in
a software source via the OS Management service in [Oracle Cloud
Infrastructure](https://www.oracle.com/cloud/).

## References

RPM website: <https://rpm.org/>

Maximum RPM book: <http://ftp.rpm.org/>

RPM Packaging Guide: <https://rpm-packaging-guide.github.io/>

RPM Howto: <https://www.tldp.org/HOWTO/RPM-HOWTO/build.html>

Mock build tool: <https://github.com/rpm-software-management/mock/wiki>
