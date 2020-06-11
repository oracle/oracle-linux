#!/usr/bin/env bash
#
# Provision instance in Oracle Cloud Infrastructure (OCI)
#
# Copyright (c) 1982-2020 Oracle and/or its affiliates. All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at
# https://oss.oracle.com/licenses/upl
#
# Description: Proof of concept / demo script for the Oracle Cloud
# Infrastructure (OCI) Command Line Interface (CLI).
#
# More info on the OCI CLI: https://github.com/oracle/oci-cli
#
# This script assumes that you have setup a default compartment id in your
# oci rc file (~/.oci/oci_cli_rc).
#

# Constants
readonly PGM=$(basename "$0")
readonly PGM_DIR=$(dirname "$0")
readonly ENV_FILE="${PGM_DIR}/$(basename ${PGM} .sh).env"

# Defaults
shape="VM.Standard2.1"
operating_system="Oracle Linux"
availability_domain="AD-1"

# Handle DOS type end of line
if [[ $OSTYPE =~ ^(msys|mingw|cygwin) ]]; then
  IFS=$' \t\r\n'
fi

#######################################
# Convenience functions
#######################################
usage() {
  cat <<-EOF
	Usage: ${PGM} OPTIONS

	  Provision an OCI compute instance.

	Options:
	  --help, -h                show this text and exit
	  --os                      operating system (default: Oracle Linux)
	  --os-version              operating system version
	  --image IMAGE             image search pattern in the Marketplace
	                            os/os-version are ignored when image is specified
	  --custom IMAGE            image search pattern for Custom images
	                            os/os-version are ignored when custom is specified
	  --name NAME               compute VM instance name
	  --shape SHAPE             VM shape (default: VM.Standard2.1)
	  --ad AD                   Availability Domain (default: AD-1)
	  --key KEY                 public key to access the instance
	  --vcn VCN                 name of the VCN to attach to the instance
	  --subnet SUBNET           name of the subnet to attach to the instance
	  --cloud-init CLOUD-INIT   optional clout-init file to provision the instance

	Default values for parameters can be stored in ${ENV_FILE}
	EOF
  exit 1
}

echo_header() {
  echo "$(tput setaf 2)+++ ${PGM}: $@$(tput sgr 0)"
}

echo_message() {
  echo "    ${PGM}: $@"
}

error() {
  echo "$(tput setaf 1)+++ ${PGM}: $@$(tput sgr 0)" >&2
  exit 1
}

missing_parameter() {
  echo "Missing parameter for $1" >&2
  usage
}

check_argument() {
  if [[ -z "$2" ]]; then
    echo "Missing $1 argument" >&2
    usage
  fi
}

#######################################
# Parse arguments
#######################################
parse_args () {
  # Source defaults from env file
  [[ -r "${ENV_FILE}" ]] && source "${ENV_FILE}"

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      "--help"|"-h")
        usage
        ;;
      "--os")
        [[ $# -lt 2 ]] && missing_parameter "os"
        operating_system="$2"
        shift; shift
        ;;
      "--os-version")
        [[ $# -lt 2 ]] && missing_parameter "os version"
        operating_system_version="$2"
        shift; shift
        ;;
      "--image")
        [[ $# -lt 2 ]] && missing_parameter "image name"
        image_name="$2"
        shift; shift
        ;;
      "--custom")
        [[ $# -lt 2 ]] && missing_parameter "image name"
        custom_image_name="$2"
        shift; shift
        ;;
      "--name")
        [[ $# -lt 2 ]] && missing_parameter "instance name"
        instance_name="$2"
        shift; shift
        ;;
      "--cloud-init")
        [[ $# -lt 2 ]] && missing_parameter "cloud-init file"
        cloud_init="$2"
        shift; shift
        ;;
      "--key")
        [[ $# -lt 2 ]] && missing_parameter "public key file"
        public_key="$2"
        shift; shift
        ;;
      "--shape")
        [[ $# -lt 2 ]] && missing_parameter "shape"
        shape="$2"
        shift; shift
        ;;
      "--ad")
        [[ $# -lt 2 ]] && missing_parameter "availability domain"
        availability_domain="$2"
        shift; shift
        ;;
      "--vcn")
        [[ $# -lt 2 ]] && missing_parameter "VCN name"
        vcn_name="$2"
        shift; shift
        ;;
      "--subnet")
        [[ $# -lt 2 ]] && missing_parameter "subnet name"
        subnet_name="$2"
        shift; shift
        ;;
      *)
        echo "Invalid argument"
        usage
        ;;
    esac
  done

  [[ ( -z ${operating_system} || -z ${operating_system_version}) &&
	  -z ${image_name} &&
	  -z ${custom_image_name} ]] && {
    echo "Expecting os or image parameter" >&2
    usage
  }
  check_argument name "${instance_name}"
  check_argument key "${public_key}"
  check_argument shape "${shape}"
  check_argument ad "${availability_domain}"
  check_argument vcn "${vcn_name}"
  check_argument subnet "${subnet_name}"
  availability_domain=$(tr [:lower:] [:upper:] <<< ${availability_domain})
  [[ ${availability_domain} =~ ^AD-[1-3]$ ]] || error "invalid AD"
}

#######################################
# Get platform image
# We retrieve the latest image for a specified os / os version
# We pass the shape to the API to ensure we get a compatible image
#######################################
get_platform_image () {
  local image_list display_name

  echo_header "Getting latest image for ${operating_system} ${operating_system_version}"
  image_list=$(oci compute image list \
    --operating-system "${operating_system}" \
    --operating-system-version "${operating_system_version}" \
    --shape ${shape} \
    --sort-by TIMECREATED \
    --query '[data[0].id, data[0]."display-name"] | join(`\n`,@)' \
    --raw-output)
  [[ -z "${image_list}" ]] && error "image not found"
  { read ocid_image; read display_name; } <<< "${image_list}"
  echo_message "Retrieved: ${display_name}"
}

#######################################
# Get custom image
# We retrieve the matching custom image
# If there is more than one match: print the list and exit
#######################################
get_custom_image () {
  local image_list display_name

  echo_header "Getting custom image list for ${custom_image_name}"
  image_list=$(oci compute image list \
    --operating-system "Custom" \
    --shape ${shape} \
    --sort-by TIMECREATED \
    --query 'data[?contains("display-name", `'"${custom_image_name}"'`)].join('"'"' '"'"', ["id", "display-name"]) | join(`\n`, @)' \
    --raw-output)

  [[ -z "${image_list}" ]] && error "No matching custom image not found"

  if [[ $(wc -l <<< "${image_list}") -gt 1 ]]; then
    echo_message "More than one image match your selection."
    while read ocid_image display_name; do
      echo -e "\t${display_name}"
    done <<< "${image_list}"
    exit
  fi

  { read ocid_image display_name; } <<< "${image_list}"

  echo_message "Selected image: ${display_name}"
}

#######################################
# Get marketplace image
# This is a bit convoluted as we need to:
# 1. Query the Partner Image Catalog to find the image
# 2. Find the latest version compatible with our shape
# 3. Get the image agreement
# 4. Accept the agreement by subscribing
#######################################
get_marketplace_image () {
  local pic_listing ocid_listing display_name
  local image_description image_summary image_version
  local available version_list
  local agreement time_retrieved signature oracle_tou_link subscription

  echo_header "Getting image listing"
  pic_listing=$(oci compute pic listing list \
    --all \
    --query 'data[?contains("display-name", `'"${image_name}"'`)].join('"'"' '"'"', ["listing-id", "display-name"]) | join(`\n`, @)' \
    --raw-output)

  [[ -z "${pic_listing}" ]] && error "No matching image found"

  if [[ $(wc -l <<< "${pic_listing}") -gt 1 ]]; then
    echo_message "More than one image match your selection."
    while read ocid_listing display_name; do
      echo -e "\t${display_name}"
    done <<< "${pic_listing}"
    exit
  fi

  read ocid_listing display_name <<< "${pic_listing}"

  # Get image details
  pic_listing=$(oci compute pic listing get --listing-id "${ocid_listing}" \
    --query '[data.description, data.summary] | join(`\n`,@)' \
    --raw-output)
  [[ -z "${pic_listing}" ]] && error "Could not get listing details"
  { read image_description; read image_summary; } <<< "${pic_listing}"
  echo_message "Selected image:"
  echo_message "Image      : ${display_name}"
  echo_message "Summary    : ${image_summary}"
  echo_message "Description: ${image_description}"

  echo_header "Getting latest image version"
  # Get all versions, sorted by latest
  available="false"
  version_list=$(oci compute pic version list --listing-id "${ocid_listing}" \
    --query 'sort_by(data,&"time-published")[*].join('"'"' '"'"',["listing-resource-version", "listing-resource-id"]) | join(`\n`, reverse(@))' \
    --raw-output)
  while read image_version ocid_image ;do
    # Ensure image is available for our shape
    available=$(oci compute pic version get --listing-id "${ocid_listing}" \
      --resource-version "${image_version}" \
      --query 'data."compatible-shapes"|contains(@, `'${shape}'`)' \
      --raw-output)
    if [[ "${available}" = "true" ]]; then
      break
    fi
    echo_message "Version ${image_version} not available for your shape; skipping"
  done <<< "${version_list}"

  if [[ "${available}" !=  "true" ]]; then
    error "No version found matching your shape"
  fi
  echo_message "Version ${image_version} selected"

  echo_header "Getting agreement and subscribing..."
  agreement=$(oci compute pic agreements get --listing-id "${ocid_listing}" \
    --resource-version  "${image_version}" \
    --query '[data."oracle-terms-of-use-link", data.signature, data."time-retrieved"] | join(`\n`,@)' \
    --raw-output)
  [[ -z "${agreement}" ]] && error "Could not get agreement"
  { read oracle_tou_link; read signature; read time_retrieved ; } <<< "${agreement}"
  echo_message "Term of use: ${oracle_tou_link}"

  # Trim time field to match recognized formats
  time_retrieved="${time_retrieved:0:23}Z"

  subscription=$(oci compute pic subscription create --listing-id "${ocid_listing}" \
    --resource-version  "${image_version}" \
    --signature "${signature}" \
    --oracle-tou-link "${oracle_tou_link}" \
    --time-retrieved "${time_retrieved}" \
    --query 'data."listing-id"' \
    --raw-output)

  [[ "${ocid_listing}" != "${subscription}" ]] && error "Subscritpion failed"
  echo_message "Subscribed"
}

#######################################
# Provision instance
#######################################
provision_instance () {
  local ocid_vcn ocid_subnet ocid_instance public_ip

  echo_header "Retrieving AD name"
  availability_domain=$(oci iam availability-domain list \
    --all \
    --query 'data[?contains(name, `'"${availability_domain}"'`)] | [0].name' \
    --raw-output)
  [[ -z "${availability_domain}" ]] && error "Could not retrieve AD name"

  echo_header "Retrieving VCN"
  ocid_vcn=$(oci network vcn list \
    --query "data [?\"display-name\"=='${vcn_name}'] | [0].id" \
    --raw-output)
  [[ -z "${ocid_vcn}" ]] && error "Could not retrieve VCN"

  echo_header "Retrieving subnet"
  ocid_subnet=$(oci network subnet list \
    --vcn-id ${ocid_vcn} \
    --query "data [?\"display-name\"=='${subnet_name}'] | [0].id" \
    --raw-output)
  [[ -z "${ocid_subnet}" ]] && error "Could not retrieve subnet"

  echo_header "Provisioning ${instance_name} with ${shape}${cloud_init:+ (${cloud_init})}"
  ocid_instance=$(oci compute instance launch \
    --display-name ${instance_name} \
    --availability-domain "${availability_domain}" \
    --subnet-id "${ocid_subnet}" \
    --image-id "${ocid_image}" \
    --shape "${shape}" \
    --ssh-authorized-keys-file "${public_key}" \
    --assign-public-ip true \
    ${cloud_init:+--user-data-file "${cloud_init}"} \
    --wait-for-state RUNNING \
    --query 'data.id' \
    --raw-output)
  [[ -z "${ocid_instance}" ]] && error "Provisioning failed"

  echo_header "Getting public IP address"
  public_ip=$(oci compute instance list-vnics \
    --instance-id "${ocid_instance}" \
    --query 'data[0]."public-ip"' \
    --raw-output)
  [[ -z "${public_ip}" ]] && error "Could not get public IP address"

  echo_message "Public IP is: ${public_ip}"
}

#######################################
# Main
#######################################
main () {
  parse_args "$@"
  if [[ -n "${image_name}" ]]; then
    get_marketplace_image
  elif [[ -n "${custom_image_name}" ]]; then
    get_custom_image
  else
    get_platform_image
  fi
  provision_instance
}

main "$@"
