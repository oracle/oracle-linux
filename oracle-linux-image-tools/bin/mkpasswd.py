#!/usr/bin/env python3

"""
Simple wrapper to generate SHA512 hash for a password.

Copyright (c) 2019-2022 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl.

Description: Python < 3.3 does not have crypt.mksalt() we mimmic
https://github.com/python/cpython/blob/master/Lib/crypt.py

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

from crypt import crypt
from random import SystemRandom
from string import ascii_letters, digits
from sys import argv, exit


def mksalt():
    """Generate SHA512 salt."""
    sr = SystemRandom()
    return '$6$' + ''.join(sr.choice(ascii_letters + digits + './')
                           for char in range(16))


if len(argv) != 2:
    print("Usage: " + argv[0] + " password")
    exit(1)

print(crypt(argv[1], mksalt()))
