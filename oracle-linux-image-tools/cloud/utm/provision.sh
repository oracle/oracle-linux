#!/usr/bin/env bash
#
# Provisioning script for UTM
#
# Copyright (c) 2022, 2024 Oracle and/or its affiliates.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: UTM specific provisioning.
#
# DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
#

#######################################
# Provisioning module
# Globals:
#   OPC_PASSWORD
# Arguments:
#   None
# Returns:
#   None
#######################################
cloud::provision()
{
  hash=$(/usr/libexec/platform-python -c "import crypt; print(crypt.crypt('${OPC_PASSWORD}', crypt.METHOD_SHA512))")
  useradd opc -c "Oracle Public Cloud User" -G wheel -m -p "${hash}"
  passwd -e opc
  echo "%opc ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers.d/opc
  chmod 0440 /etc/sudoers.d/opc
  restorecon /etc/sudoers.d/opc
}
