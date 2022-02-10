#!/usr/bin/env python3

"""Main package file.

Import classes, exceptions and enums
"""
import pkg_resources

try:
    __version__ = pkg_resources.get_distribution('setuptools').version
except Exception:
    __version__ = 'unknown'
