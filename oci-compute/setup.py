#!/usr/bin/env python3

"""OCI Compute - and Oracle Cloud Infrastructure Python SDK use case.

Project setup file.

Copyright (c) 2020-2022 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

SPDX-License-Identifier: UPL-1.0
"""

from os import path

from setuptools import find_packages, setup

here = path.abspath(path.dirname(__file__))
with open(path.join(here, 'README.md'), encoding='utf-8') as f:
    long_description = f.read()

setup(
    name='oci-compute',
    version='0.2.0',
    description='List and provision OCI Compute images',
    long_description=long_description,
    long_description_content_type='text/markdown',
    url='https://github.com/oracle/ol-sample-scripts',
    author='Philippe Vanhaesendonck',
    author_email='philippe.vanhaesendonck@oracle.com',
    classifiers=[
        'Development Status :: 4 - Beta',
        'Intended Audience :: Developers',
        'Topic :: Software Development :: Libraries',
        'License :: OSI Approved :: Universal Permissive License (UPL)',
        'Programming Language :: Python :: 3',
        'Operating System :: POSIX :: Linux',
    ],
    packages=find_packages(),
    python_requires='>=3.5',
    install_requires=[
        'click>=7.0',
        'oci>=2.23',
        'terminaltables>=3.1',
    ],
    entry_points={
        'console_scripts': [
            'oci-compute=oci_compute.cli:cli',
        ],
    },

)
