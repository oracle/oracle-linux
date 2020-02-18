#!/bin/bash
#
# Sample cloud-init script for OCI
#
# Copyright (c) 1982-2020 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl.
#
# Description: Run by cloud-init at instance provisioning.
#   - install lightweight X server (fluxbox) in case we need a GUI
#   - install python3
#   - install Docker / docker-compose
#   - open http/https ports on the firewall

readonly PGM=$(basename $0)
readonly YUM_OPTS="-d1 -y"
readonly USER="opc"
readonly USER_HOME=$(eval echo ~${USER})
readonly VNC_PASSWORD="MySecretVNCPassword"

#######################################
# Print header
# Globals:
#   PGM
#######################################
echo_header() {
  echo "+++ ${PGM}: $@"
}

#######################################
# Install FluxBox
# Globals:
#   USER, YUM_OPTS
#######################################
install_fluxbox() {
  echo_header "Install Fluxbox"
  yum install ${YUM_OPTS} fluxbox xterm xmessage xorg-x11-fonts-misc
  yum install ${YUM_OPTS} tigervnc-server

  su - ${USER} -c "\
    mkdir .vnc; \
    echo \"${VNC_PASSWORD}\" |  vncpasswd -f > .vnc/passwd; \
    chmod 0600 .vnc/passwd; \
    vncserver; \
    sleep 5;
    vncserver -kill :1; \
    sed -i -e 's!/etc/X11/xinit/xinitrc!/usr/bin/fluxbox!' .vnc/xstartup; \
    "
}

#######################################
# Install Python 3
# Globals:
#   USER, USER_HOME, YUM_OPTS
#######################################
install_python3() {
  echo_header "Install Python 3"
  yum install ${YUM_OPTS} python3 python3-pip

  su - ${USER} -c "pip3 install --user --upgrade pip"

  echo 'export PATH=~/.local/bin:"${PATH}"' >> ${USER_HOME}/.bash_profile

  su - ${USER} -c "\
    pip3 install --user flake8 \
    flake8-colors \
    flake8-comprehensions \
    flake8-docstrings \
    flake8-import-order; \
    "
}

#######################################
# Install docker
# Globals:
#   USER, YUM_OPTS
#######################################
install_docker() {
  echo_header "Install Docker"
  yum install ${YUM_OPTS} docker-engine

  # Add User to docker group
  usermod -a -G docker ${USER}

  # Enable and start Docker
  systemctl enable docker
  systemctl start docker

  su - ${USER} -c "pip3 install --user docker-compose"
}

#######################################
# Configure Firewall
#######################################
configure_firewall() {
  echo_header "Configure Firewall"
  local services="http https"
  local service

  for service in ${services}; do
    firewall-cmd --zone=public --add-service=${service}
    firewall-cmd --zone=public --add-service=${service} --permanent
  done
}

#######################################
# Main
#######################################
main() {
  install_python3
  install_fluxbox
  install_docker      # docker-compose depends on python3
  configure_firewall
}

main "$@"
