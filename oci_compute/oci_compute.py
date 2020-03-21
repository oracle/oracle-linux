"""OCI Compute main class.

The OciCompute class executes the OCI related tasks.

Copyright (c) 1982-2020 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl.

SPDX-License-Identifier: UPL-1.0
"""
from os.path import basename
import sys

from click import confirm, secho
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
        self._market = oci.marketplace.MarketplaceClient(self._config)

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

    def list_market(self):
        """List images from the Marketplace."""
        response = oci.pagination.list_call_get_all_results(self._market.list_listings, pricing=['FREE'])
        listings = set()
        for listing in response.data:
            listings.add((listing.publisher.name, listing.name))

        return sorted(listings)

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

    def provision_custom(self,
                         display_name,
                         compartment_id,
                         custom_image_name,
                         shape,
                         availability_domain,
                         vcn_name,
                         subnet_name,
                         ssh_authorized_keys_file,
                         cloud_init_file=None):
        """Provision Custom image."""
        self._echo_header('Retrieving image details')
        response = self._compute.list_images(
            compartment_id,
            operating_system='Custom',
            shape=shape,
            sort_by='DISPLAYNAME',
            sort_order='ASC')
        # Find matching names
        images = []
        for image in response.data:
            if custom_image_name in image.display_name:
                images.append(image)
        if len(images) == 0:
            self._echo_error("No image found")
            return None
        elif len(images) > 1:
            self._echo_error("More than one image found: {}".format(
                (', ').join([i.display_name for i in images])))
            return None

        return self._provision_image(images[0],
                                     compartment_id=compartment_id,
                                     display_name=display_name,
                                     shape=shape,
                                     availability_domain=availability_domain,
                                     vcn_name=vcn_name,
                                     subnet_name=subnet_name,
                                     ssh_authorized_keys_file=ssh_authorized_keys_file,
                                     cloud_init_file=cloud_init_file)

    def _get_listing_details(self, listing_id):
        """Return package and AppCatalogListingResourceVersion for a listing."""
        # Get latest package for the listing
        response = self._market.list_packages(listing_id, sort_by='TIMERELEASED', sort_order='DESC')
        packages = response.data
        if not packages:
            self._echo_error('Could not get package for this listing')
            return None
        package = packages[0]

        # Get package detailed info
        response = self._market.get_package(package.listing_id, package.package_version)
        package = response.data
        if not package:
            self._echo_error('Could not get package details')
            return None

        # Query the app catalog for shape/region compatibility
        response = self._compute.get_app_catalog_listing_resource_version(
            package.app_catalog_listing_id, package.app_catalog_listing_resource_version)
        aclrv = response.data
        if not aclrv:
            self._echo_error('Could not get details from the App Catalog')
            return None

        return (package, aclrv)

    def provision_market(self,
                         display_name,
                         compartment_id,
                         market_image_name,
                         shape,
                         availability_domain,
                         vcn_name,
                         subnet_name,
                         ssh_authorized_keys_file,
                         cloud_init_file=None):
        """Provision Marketplace image."""
        self._echo_header('Retrieving Marketplace listing')
        response = oci.pagination.list_call_get_all_results(self._market.list_listings, pricing=['FREE'])
        listings = []
        for listing in response.data:
            if market_image_name in listing.name:
                listings.append(listing)
        if len(listings) == 0:
            self._echo_error("No image found")
            return None
        elif len(listings) > 1:
            self._echo_error("More than one image found:")
            for name in sorted(l.name for l in listings):
                self._echo_error('    {}'.format(name))
            return None
        listing = listings[0]
        self._echo_message_kv('Publisher', listing.publisher.name)
        self._echo_message_kv('Image', listing.name)
        self._echo_message_kv('Description', listing.short_description)

        self._echo_header('Retrieving listing details')
        details = self._get_listing_details(listing.id)
        if details is None:
            return None
        (package, aclrv) = details
        self._echo_message_kv('Latest version', package.version)
        self._echo_message_kv('Released', package.time_created)

        if self._config['region'] not in aclrv.available_regions:
            self._echo_error('This image is not available in your region')
            return None

        if shape not in aclrv.compatible_shapes:
            self._echo_error('This image is not compatible with the selected shape')
            return None

        self._echo_header('Lists terms of use agreements')
        response = self._market.list_agreements(package.listing_id, package.version)
        agreements = response.data

        self._echo_header('Check acceptance agreements')
        not_accepted = []
        for agreement in agreements:
            # not correct, will return all accepted in array...
            accepted_agreements = self._market.list_accepted_agreements(
                compartment_id,
                listing_id=package.listing_id,
                package_version=package.version).data
            if not accepted_agreements:
                not_accepted.append(agreement)
            else:
                print(agreement)
                print(accepted_agreements)

        if not_accepted:
            self._echo_error('This image is subject to the following agreement(s):')
            for agreement in not_accepted:
                self._echo_error('- {}'.format(agreement.prompt))
                self._echo_error('  Link: {}'.format(agreement.content_url))
            if confirm('I have reviewed and accept the above agreement(s)'):
                # need to accept these...
                self._echo_header('Get agreements')
                for agreement in agreements:
                    response = self._market.get_agreement(package.listing_id, package.version, agreement.id)
                    print(response.data)
                    accepted_agreement = oci.marketplace.models.CreateAcceptedAgreementDetails(
                        agreement_id=agreement.id,
                        compartment_id=compartment_id,
                        listing_id=package.listing_id,
                        package_version=package.version,
                        signature=response.data.signature)
                    response = self._market.create_accepted_agreement(accepted_agreement)
                    print(response.data)
            else:
                self._echo_error('Agreements not accepted')
                return None
        else:
            self._echo_header('Agreements already accepted')

        acs = self._compute.list_app_catalog_subscriptions(
            compartment_id=compartment_id,
            listing_id=aclrv.listing_id
        ).data
        self._echo_header('Get ACS')
        print(acs)
        if not acs:
            self._echo_header('No ACS')
            acla = self._compute.get_app_catalog_listing_agreements(
                listing_id=aclrv.listing_id,
                resource_version=aclrv.listing_resource_version).data
            print(acla)
            acsd = oci.core.models.CreateAppCatalogSubscriptionDetails(
                compartment_id=compartment_id,
                listing_id=acla.listing_id,
                listing_resource_version=acla.listing_resource_version,
                oracle_terms_of_use_link=acla.oracle_terms_of_use_link,
                eula_link=acla.eula_link,
                signature=acla.signature,
                time_retrieved=acla.time_retrieved
            )
            print(acsd)
            self._echo_header('Create ACS')
            acs = self._compute.create_app_catalog_subscription(acsd).data
            print(acs)

        self._echo_header('Proceeding')
        image = self._compute.get_image(aclrv.listing_resource_id).data
        return self._provision_image(image,
                                     compartment_id=compartment_id,
                                     display_name=display_name,
                                     shape=shape,
                                     availability_domain=availability_domain,
                                     vcn_name=vcn_name,
                                     subnet_name=subnet_name,
                                     ssh_authorized_keys_file=ssh_authorized_keys_file,
                                     cloud_init_file=cloud_init_file)
