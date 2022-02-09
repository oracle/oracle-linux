#!/usr/bin/env python3

"""OCI Compute rc file helper.

RcFile helper class to get default values from the oci_compute rc file.

Copyright (c) 2020-2022 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

SPDX-License-Identifier: UPL-1.0
"""
from configparser import ConfigParser, DEFAULTSECT

# Default values for rc file variables
DEFAULT_RC_VARS = {
    'operating-system': 'Oracle Linux',
    'shape': 'VM.Standard2.1',
    'availability-domain': 'AD-1',
    'subnet-name': 'Public Subnet',
    'ssh-authorized-keys-file': '~/.ssh/id_rsa.pub',
}


class RcFile():
    """Store key pairs from rc file."""

    def __init__(self, rc_file, profile):
        """Load parameters from the RC file."""
        self._rc_vars = DEFAULT_RC_VARS
        if rc_file:
            config = ConfigParser(interpolation=None)
            config.read(rc_file)
            # Profile section is optional
            if not config.has_section(profile):
                profile = DEFAULTSECT
            for key in config[profile]:
                self._rc_vars[key] = config[profile][key]

    @staticmethod
    def get_default(variable):
        """Get default value for a variable."""
        return DEFAULT_RC_VARS.get(variable)

    def get_default_rc(self, variable):
        """Get default value for a parameter, taking in account the RC file."""
        return self._rc_vars.get(variable)
