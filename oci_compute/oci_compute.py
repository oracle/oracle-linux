"""OCI Compute main class.

The OciCompute class executes the OCI related tasks.

Copyright (c) 1982-2020 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl.

SPDX-License-Identifier: UPL-1.0
"""
from os.path import basename
import sys

from click import secho
import oci


class OciCompute(object):
    """Main class."""

    def __init__(self,
                 config_file,
                 profile,
                 verbose=False):
        """Initialise the class.

        Config files are read and validated, clients are instantiated.
        """
        self._verbose = verbose
        self._cli = format(basename(sys.argv[0]))

        # Load OCI config file
        self._config = oci.config.from_file(config_file, profile)

        # Instantiate clients
        self._compute = oci.core.ComputeClient(self._config)
        self._identity = oci.identity.IdentityClient(self._config)
        self._virtual_network = oci.core.VirtualNetworkClient(self._config)

    def _echo_header(self, message):
        if self._verbose:
            secho('+++ {}: {}'.format(self._cli, message), fg='green')

    def _echo_message(self, message):
        if self._verbose:
            secho('    {}: {}'.format(self._cli, message))

    def _echo_message_kv(self, key, value):
        if self._verbose:
            secho('    {}: {:25}: {}'.format(self._cli, key, value))

    def _echo_error(self, message):
        secho('+++ {}: {}'.format(self._cli, message), fg='red', err=True)

    def list_platform(self, compartment_id):
        """List platform images.

        Parameters:
            compartment_id: the compartment OCID

        """
        response = oci.pagination.list_call_get_all_results(self._compute.list_images, compartment_id)
        images = set()
        for image in response.data:
            if image.operating_system != 'Custom':
                images.add((image.operating_system, image.operating_system_version))

        return sorted(images)

    def list_custom(self, compartment_id):
        """List custom images.

        Parameters:
            compartment_id: the compartment OCID

        """
        response = oci.pagination.list_call_get_all_results(self._compute.list_images, compartment_id)
        images = set()
        for image in response.data:
            if image.operating_system == 'Custom':
                images.add((image.display_name, image.time_created))

        return sorted(images)

    def _get_availability_domain(self, compartment_id, availability_domain):
        """Retrieve the Availability Domain.

        Parameters:
            availability_domain: Availability Domain like 'AD-1'
            compartment_id: Compartment OCID
        """
        self._echo_header('Retrieving Availability Domain')
        response = oci.pagination.list_call_get_all_results(self._identity.list_availability_domains, compartment_id)

        ad_match = [ad for ad in response.data if availability_domain.upper() in ad.name]

        if ad_match:
            self._echo_message_kv('Name', ad_match[0].name)
            return ad_match[0]
        else:
            self._echo_error('No AD found matching "{}"'.format(availability_domain))
            return None

    def _get_subnet(self, compartment_id, vcn_name, subnet_name):
        """Retrieve the Availability Domain.

        Parameters:
            vcn: VCN display name
            subnet_name: subnet display name
            compartment_id: Compartment OCID
        """
        self._echo_header('Retrieving VCN')
        response = self._virtual_network.list_vcns(compartment_id, display_name=vcn_name)

        if not response.data:
            self._echo_error('No matching VCN for "{}"'.format(vcn_name))
            return None

        vcn = response.data[0]
        self._echo_message_kv('Name', vcn.display_name)

        self._echo_header('Retrieving subnet')
        response = self._virtual_network.list_subnets(compartment_id, vcn.id, display_name=subnet_name)

        if not response.data:
            self._echo_error('No matching subnet for "{}"'.format(subnet_name))
            return None
        else:
            self._echo_message_kv('Subnet', response.data[0].display_name)
            return response.data[0]

    def get_vnic(self,
                 compartment_id,
                 instance):
        """Get VNIC data for the instance."""
        self._echo_header('Retrieving VNIC attachments')
        response = oci.pagination.list_call_get_all_results(
            self._compute.list_vnic_attachments,
            compartment_id=compartment_id, instance_id=instance.id)

        if not response.data:
            self._echo_error('Could not retrieve VNIC attachments')
            return None

        vnic_attachment = response.data[0]
        self._echo_message_kv('NIC attached - Index', vnic_attachment.nic_index)

        self._echo_header('Retrieving VNIC data')
        response = self._virtual_network.get_vnic(vnic_attachment.vnic_id)
        vnic = response.data

        if not vnic:
            self._echo_error('  Could not retrieve VNIC data')
            return None

        self._echo_message_kv('Private IP', vnic.private_ip)
        self._echo_message_kv('Public IP', vnic.public_ip)

        return vnic

    def _provision_image(self,
                         image,
                         compartment_id,
                         display_name,
                         shape,
                         availability_domain,
                         vcn_name,
                         subnet_name,
                         ssh_authorized_keys_file,
                         cloud_init_file):
        """Actual image provisioning."""
        self._echo_header('Image selected:')
        self._echo_message_kv('Name', image.display_name)
        self._echo_message_kv('Created', image.time_created)
        self._echo_message_kv('Operating System', image.operating_system)
        self._echo_message_kv('Operating System version', image.operating_system_version)

        availability_domain = self._get_availability_domain(compartment_id, availability_domain)
        if not availability_domain:
            return None

        subnet = self._get_subnet(compartment_id, vcn_name, subnet_name)
        if not subnet:
            return None

        self._echo_header('Creating and launching instance')
        # https://github.com/oracle/oci-python-sdk/blob/master/examples/launch_instance_example.py
        instance_source_details = oci.core.models.InstanceSourceViaImageDetails(image_id=image.id)

        create_vnic_details = oci.core.models.CreateVnicDetails(subnet_id=subnet.id)

        # Metadata with the ssh keys and the cloud-init file
        metadata = {}
        with open(ssh_authorized_keys_file) as ssh_authorized_keys:
            metadata['ssh_authorized_keys'] = ssh_authorized_keys.read()

        if cloud_init_file:
            metadata['user_data'] = oci.util.file_content_as_launch_instance_user_data(cloud_init_file)

        launch_instance_details = oci.core.models.LaunchInstanceDetails(
            display_name=display_name,
            compartment_id=compartment_id,
            availability_domain=availability_domain.name,
            shape=shape,
            metadata=metadata,
            source_details=instance_source_details,
            create_vnic_details=create_vnic_details)

        compute_composite_operations = oci.core.ComputeClientCompositeOperations(self._compute)

        response = compute_composite_operations.launch_instance_and_wait_for_state(
            launch_instance_details,
            wait_for_states=[oci.core.models.Instance.LIFECYCLE_STATE_RUNNING])
        instance = response.data

        if not instance:
            self._echo_error('Instance launch failed')
            self._echo_error('Response: {}'.format(response))
            return None
        else:
            self._echo_message_kv('Name', instance.display_name)
            self._echo_message_kv('State', instance.lifecycle_state)
            self._echo_message_kv('Time created', instance.time_created)

        return instance

    def provision_platform(self,
                           display_name,
                           compartment_id,
                           operating_system,
                           operating_system_version,
                           shape,
                           availability_domain,
                           vcn_name,
                           subnet_name,
                           ssh_authorized_keys_file,
                           cloud_init_file=None):
        """Provision platform image."""
        self._echo_header('Retrieving image details')
        response = self._compute.list_images(
            compartment_id,
            operating_system=operating_system,
            operating_system_version=operating_system_version,
            shape=shape,
            sort_by='TIMECREATED',
            sort_order='DESC')
        if len(response.data) == 0:
            self._echo_error("No image found")
            return None
        image = response.data[0]
        return self._provision_image(image,
                                     compartment_id=compartment_id,
                                     display_name=display_name,
                                     shape=shape,
                                     availability_domain=availability_domain,
                                     vcn_name=vcn_name,
                                     subnet_name=subnet_name,
                                     ssh_authorized_keys_file=ssh_authorized_keys_file,
                                     cloud_init_file=cloud_init_file)
