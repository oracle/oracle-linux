#!/usr/bin/env python3

"""OCI Compute main class.

The OciCompute class interfaces with the OCI SDK.

Copyright (c) 2020-2022 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

SPDX-License-Identifier: UPL-1.0
"""
from os.path import basename
import sys

from click import confirm, echo, secho
import oci


# OS name for Custom images
CUSTOM_OS = ('Custom', 'Zero')


class OciCompute(object):
    """Interface with the OCI SDK."""

    def __init__(self,
                 config_file,
                 profile,
                 verbose=False):
        """Initialise the class.

        Config files are read and validated, SDK clients are instantiated.
        """
        self._verbose = verbose
        self._cli = format(basename(sys.argv[0]))

        # Load OCI config file
        self._config = oci.config.from_file(config_file, profile)

        # Instantiate clients
        self._compute_client = oci.core.ComputeClient(self._config)
        self._identity_client = oci.identity.IdentityClient(self._config)
        self._virtual_network_client = oci.core.VirtualNetworkClient(self._config)
        self._marketplace_client = oci.marketplace.MarketplaceClient(self._config)

    """Helpers to display messages."""

    def _echo_header(self, message, force=False):
        """Display message header in verbose/forced mode."""
        if self._verbose or force:
            secho('+++ {}: {}'.format(self._cli, message), fg='green')

    def _echo_message(self, message, force=False, nl=True):
        """Display message in verbose/forced mode."""
        if self._verbose or force:
            echo('    {}: {}'.format(self._cli, message), nl=nl)

    def _echo_message_kv(self, key, value, force=False):
        """Display key/value pair in verbose/forced mode."""
        if self._verbose or force:
            echo('    {}: {:25}: {}'.format(self._cli, key, value))

    def _echo_error(self, message):
        """Display error message."""
        secho('+++ {}: {}'.format(self._cli, message), fg='red', err=True)

    def _echo(self, message='', force=False, nl=True):
        """Display raw message in verbose/forced mode."""
        if self._verbose or force:
            echo(message, nl=nl)

    def _get_availability_domain(self, compartment_id, availability_domain):
        """Retrieve matching Availability Domain name.

        Parameters:
            availability_domain: abbreviated Availability Domain like 'AD-1'
            compartment_id: Compartment OCID

        """
        self._echo_header('Retrieving Availability Domain')
        availability_domains = oci.pagination.list_call_get_all_results(
            self._identity_client.list_availability_domains,
            compartment_id
        ).data

        ad_match = [ad for ad in availability_domains if availability_domain.upper() in ad.name]

        if ad_match:
            self._echo_message_kv('Name', ad_match[0].name)
            return ad_match[0]
        else:
            self._echo_error('No AD found matching "{}"'.format(availability_domain))
            return None

    def _wait_callback(self, times, result):
        """Wait animation for oci.wait_until."""
        self._echo('.', nl=False)

    def _get_subnet(self, compartment_id, vcn_name, subnet_name):
        """Retrieve the matching subnet in a VCN.

        Parameters:
            vcn: VCN display name
            subnet_name: subnet display name
            compartment_id: Compartment OCID

        """
        self._echo_header('Retrieving VCN')
        vcns = self._virtual_network_client.list_vcns(compartment_id, display_name=vcn_name).data

        if not vcns:
            self._echo_error('No matching VCN for "{}"'.format(vcn_name))
            return None

        vcn = vcns[0]
        self._echo_message_kv('Name', vcn.display_name)

        self._echo_header('Retrieving subnet')
        subnets = self._virtual_network_client.list_subnets(compartment_id,
                                                            vcn_id=vcn.id,
                                                            display_name=subnet_name).data

        if not subnets:
            self._echo_error('No matching subnet for "{}"'.format(subnet_name))
            return None
        else:
            subnet = subnets[0]
            self._echo_message_kv('Subnet', subnet.display_name)
            return subnet

    def _market_agreements(self,
                           compartment_id,
                           listing_id,
                           version):
        """Ensure image Terms Of Use are accepted.

        For Marketplace images, the various Terms Of Use need to be accepted.
        This method search for already accepted TOU and prompt for acceptance if
        needed.

        Parameters:
            compartment_id: the unique identifier for the compartment.
            listing_id: the unique identifier for the listing.
            version: the version of the package.

        Returns:
            True if TOU are accepted. False otherwise.

        """
        self._echo_header('Checking agreements acceptance')
        agreements = self._marketplace_client.list_agreements(listing_id, version).data
        accepted_agreements = self._marketplace_client.list_accepted_agreements(
            compartment_id,
            listing_id=listing_id,
            package_version=version).data
        not_accepted = []
        for agreement in agreements:
            agreement_match = [accepted_agreement
                               for accepted_agreement in accepted_agreements
                               if agreement.id == accepted_agreement.agreement_id]
            if not agreement_match:
                not_accepted.append(agreement)

        if not_accepted:
            self._echo_message('This image is subject to the following agreement(s):', force=True)
            for agreement in not_accepted:
                self._echo_message('- {}'.format(agreement.prompt), force=True)
                self._echo_message('  Link: {}'.format(agreement.content_url), force=True)
            if confirm('I have reviewed and accept the above agreement(s)'):
                self._echo_message('Accepting agreement(s)')
                for agreement in not_accepted:
                    agreement_detail = self._marketplace_client.get_agreement(
                        listing_id,
                        version,
                        agreement.id).data
                    accepted_agreement_details = oci.marketplace.models.CreateAcceptedAgreementDetails(
                        agreement_id=agreement.id,
                        compartment_id=compartment_id,
                        listing_id=listing_id,
                        package_version=version,
                        signature=agreement_detail.signature)
                    self._marketplace_client.create_accepted_agreement(accepted_agreement_details)
            else:
                self._echo_error('Agreements not accepted')
                return False
        else:
            self._echo_message('Agreements already accepted')
        return True

    def _app_catalog_subscribe(self,
                               compartment_id,
                               listing_id,
                               resource_version):
        """Subscribe to the image in the Application Catalog.

        For Marketplace images, we also need to subscribe to the image in the
        Application Catalog. We do not prompt for the TOU as we already agreed
        in the Marketplace.

        Parameters:
            compartment_id: the unique identifier for the compartment.
            listing_id: the OCID of the listing.
            resource_version: Listing Resource Version.

        """
        self._echo_header('Checking Application Catalog subscription')
        app_catalog_subscriptions = self._compute_client.list_app_catalog_subscriptions(
            compartment_id=compartment_id,
            listing_id=listing_id
        ).data
        if app_catalog_subscriptions:
            self._echo_message('Already subscribed')
        else:
            self._echo_message('Subscribing')
            app_catalog_listing_agreements = self._compute_client.get_app_catalog_listing_agreements(
                listing_id=listing_id,
                resource_version=resource_version).data
            app_catalog_subscription_detail = oci.core.models.CreateAppCatalogSubscriptionDetails(
                compartment_id=compartment_id,
                listing_id=app_catalog_listing_agreements.listing_id,
                listing_resource_version=app_catalog_listing_agreements.listing_resource_version,
                oracle_terms_of_use_link=app_catalog_listing_agreements.oracle_terms_of_use_link,
                eula_link=app_catalog_listing_agreements.eula_link,
                signature=app_catalog_listing_agreements.signature,
                time_retrieved=app_catalog_listing_agreements.time_retrieved
            )
            self._compute_client.create_app_catalog_subscription(app_catalog_subscription_detail).data

    def _provision_image(self,
                         image,
                         compartment_id,
                         display_name,
                         shape,
                         availability_domain,
                         vcn_name,
                         vcn_compartment_id,
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

        subnet = self._get_subnet(vcn_compartment_id if vcn_compartment_id else compartment_id, vcn_name, subnet_name)
        if not subnet:
            return None

        self._echo_header('Creating and launching instance')
        instance_source_via_image_details = oci.core.models.InstanceSourceViaImageDetails(image_id=image.id)
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
            source_details=instance_source_via_image_details,
            create_vnic_details=create_vnic_details)

        compute_client_composite_operations = oci.core.ComputeClientCompositeOperations(self._compute_client)

        self._echo_message('Waiting for Running state', nl=False)
        response = compute_client_composite_operations.launch_instance_and_wait_for_state(
            launch_instance_details,
            wait_for_states=[oci.core.models.Instance.LIFECYCLE_STATE_RUNNING],
            waiter_kwargs={'wait_callback': self._wait_callback})
        self._echo()
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

    """Public methods."""

    def list_platform(self, compartment_id):
        """List platform images.

        Parameters:
            compartment_id: the compartment OCID

        """
        response = oci.pagination.list_call_get_all_results(self._compute_client.list_images, compartment_id)
        images = set()
        for image in response.data:
            if image.operating_system not in CUSTOM_OS:
                images.add((image.operating_system, image.operating_system_version))

        return sorted(images)

    def list_custom(self, compartment_id):
        """List custom images.

        Parameters:
            compartment_id: the compartment OCID

        """
        response = oci.pagination.list_call_get_all_results(self._compute_client.list_images, compartment_id)
        images = set()
        for image in response.data:
            if image.operating_system in CUSTOM_OS:
                images.add((image.display_name, image.time_created))

        return sorted(images)

    def list_market(self):
        """List images from the Marketplace."""
        response = oci.pagination.list_call_get_all_results(self._marketplace_client.list_listings, pricing=['FREE'])
        listings = set()
        for listing in response.data:
            listings.add((listing.publisher.name, listing.name))

        return sorted(listings)

    def get_vnic(self,
                 compartment_id,
                 instance):
        """Get VNIC data for the instance."""
        self._echo_header('Retrieving VNIC attachments')
        vnic_attachments = oci.pagination.list_call_get_all_results(
            self._compute_client.list_vnic_attachments,
            compartment_id=compartment_id, instance_id=instance.id).data

        if not vnic_attachments:
            self._echo_error('Could not retrieve VNIC attachments')
            return None

        # Walk through attachments to find primary. If no primary found (should
        # not happen) returns last one.
        vnic = None
        for vnic_attachment in vnic_attachments:
            try:
                vnic = self._virtual_network_client.get_vnic(vnic_attachment.vnic_id).data
            except oci.exceptions.ServiceError:
                vnic = None
            if vnic and vnic.is_primary:
                break

        if not vnic:
            self._echo_error('  Could not retrieve VNIC data')
            return None

        self._echo_message_kv('Private IP', vnic.private_ip)
        self._echo_message_kv('Public IP', vnic.public_ip)

        return vnic

    def provision_platform(self,
                           display_name,
                           compartment_id,
                           operating_system,
                           operating_system_version,
                           shape,
                           availability_domain,
                           vcn_name,
                           vcn_compartment_id,
                           subnet_name,
                           ssh_authorized_keys_file,
                           cloud_init_file=None):
        """Provision platform image."""
        self._echo_header('Retrieving image details')
        images = self._compute_client.list_images(
            compartment_id,
            operating_system=operating_system,
            operating_system_version=operating_system_version,
            shape=shape,
            sort_by='TIMECREATED',
            sort_order='DESC').data
        if not images:
            self._echo_error("No image found")
            return None
        image = images[0]
        return self._provision_image(image,
                                     compartment_id=compartment_id,
                                     display_name=display_name,
                                     shape=shape,
                                     availability_domain=availability_domain,
                                     vcn_name=vcn_name,
                                     vcn_compartment_id=vcn_compartment_id,
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
                         vcn_compartment_id,
                         subnet_name,
                         ssh_authorized_keys_file,
                         cloud_init_file=None):
        """Provision Custom image."""
        self._echo_header('Retrieving image details')
        response = self._compute_client.list_images(
            compartment_id,
            shape=shape,
            sort_by='DISPLAYNAME',
            sort_order='ASC')
        # Find matching names
        images = []
        for image in response.data:
            if image.operating_system in CUSTOM_OS and custom_image_name in image.display_name:
                images.append(image)
        if not images:
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
                                     vcn_compartment_id=vcn_compartment_id,
                                     subnet_name=subnet_name,
                                     ssh_authorized_keys_file=ssh_authorized_keys_file,
                                     cloud_init_file=cloud_init_file)

    def provision_market(self,
                         display_name,
                         compartment_id,
                         market_image_name,
                         shape,
                         availability_domain,
                         vcn_name,
                         vcn_compartment_id,
                         subnet_name,
                         ssh_authorized_keys_file,
                         cloud_init_file=None):
        """Provision Marketplace image."""
        self._echo_header('Retrieving Marketplace listing')
        response = oci.pagination.list_call_get_all_results(self._marketplace_client.list_listings, pricing=['FREE'])
        listings = []
        for listing in response.data:
            if market_image_name in listing.name:
                listings.append(listing)
        if not listings:
            self._echo_error("No image found")
            return None
        elif len(listings) > 1:
            self._echo_error("More than one image found:")
            for name in sorted(listing.name for listing in listings):
                self._echo_error('    {}'.format(name))
            return None
        listing = listings[0]
        self._echo_message_kv('Publisher', listing.publisher.name)
        self._echo_message_kv('Image', listing.name)
        self._echo_message_kv('Description', listing.short_description)

        self._echo_header('Retrieving listing details')
        packages = self._marketplace_client.list_packages(listing.id, sort_by='TIMERELEASED', sort_order='DESC').data
        if not packages:
            self._echo_error('Could not get package for this listing')
            return None
        package = packages[0]

        # Get package detailed info
        package = self._marketplace_client.get_package(package.listing_id, package.package_version).data
        if not package:
            self._echo_error('Could not get package details')
            return None

        # Query the Application Catalog for shape/region compatibility
        # Note that the listing_id/version are different in the Marketplace and
        # in the Application Catalog!
        app_catalog_listing_resource_version = self._compute_client.get_app_catalog_listing_resource_version(
            package.app_catalog_listing_id,
            package.app_catalog_listing_resource_version).data
        if not app_catalog_listing_resource_version:
            self._echo_error('Could not get details from the App Catalog')
            return None
        self._echo_message_kv('Latest version', package.version)
        self._echo_message_kv('Released', package.time_created)

        if self._config['region'] not in app_catalog_listing_resource_version.available_regions:
            self._echo_error('This image is not available in your region')
            return None

        if shape not in app_catalog_listing_resource_version.compatible_shapes:
            self._echo_error('This image is not compatible with the selected shape')
            return None

        # Accept Marketplace Terms of Use
        if not self._market_agreements(compartment_id, package.listing_id, package.version):
            return None

        # Subscribe to the listing in the Application Catalog
        self._app_catalog_subscribe(
            compartment_id,
            app_catalog_listing_resource_version.listing_id,
            app_catalog_listing_resource_version.listing_resource_version)

        # Retrieve image from the Application Catalog
        image = self._compute_client.get_image(app_catalog_listing_resource_version.listing_resource_id).data

        # Actual provisioning
        return self._provision_image(image,
                                     compartment_id=compartment_id,
                                     display_name=display_name,
                                     shape=shape,
                                     availability_domain=availability_domain,
                                     vcn_name=vcn_name,
                                     vcn_compartment_id=vcn_compartment_id,
                                     subnet_name=subnet_name,
                                     ssh_authorized_keys_file=ssh_authorized_keys_file,
                                     cloud_init_file=cloud_init_file)

    def instance_list(self, compartment_id, display_name=None):
        """List Compute Instances.

        Parameters:
            compartment_id: the compartment OCID
            display_name: A filter to return only resources that match the
                          given display name exactly

        """
        response = oci.pagination.list_call_get_all_results(
            self._compute_client.list_instances,
            compartment_id,
            display_name=display_name)
        instances = []
        for instance in response.data:
            if instance.lifecycle_state == 'TERMINATED':
                continue
            vnic = self.get_vnic(compartment_id, instance)
            instances.append((
                instance.id,
                instance.display_name,
                instance.availability_domain[-4:],
                instance.time_created.strftime("%Y-%m-%d %H:%M:%S %Z"),
                instance.lifecycle_state.title(),
                vnic.private_ip if vnic else 'None',
                vnic.public_ip if vnic else 'None'
            ))

        return instances

    def instance_terminate(self, instance_id, wait=False):
        """Terminate Compute Instance.

        Parameters:
            instance_id: the OCID of the instance
            wait: wait for completion (True/False)

        """
        self._echo_header('Termination initiated')
        if wait:
            compute_client_composite_operations = oci.core.ComputeClientCompositeOperations(self._compute_client)
            self._echo_message('Waiting for termination', nl=False)
            compute_client_composite_operations.terminate_instance_and_wait_for_state(
                instance_id=instance_id,
                wait_for_states=[oci.core.models.Instance.LIFECYCLE_STATE_TERMINATED],
                waiter_kwargs={'wait_callback': self._wait_callback})
            self._echo()
        else:
            self._compute_client.terminate_instance(instance_id, preserve_boot_volume=False)

    def instance_start(self, instance_id, wait=False):
        """Start Compute Instance.

        Parameters:
            instance_id: the OCID of the instance
            wait: wait for completion (True/False)

        """
        self._echo_header('Startup initiated')
        if wait:
            compute_client_composite_operations = oci.core.ComputeClientCompositeOperations(self._compute_client)
            self._echo_message('Waiting for Running state', nl=False)
            compute_client_composite_operations.instance_action_and_wait_for_state(
                instance_id=instance_id,
                action='START',
                wait_for_states=[oci.core.models.Instance.LIFECYCLE_STATE_RUNNING],
                waiter_kwargs={'wait_callback': self._wait_callback})
            self._echo()
        else:
            self._compute_client.instance_action(instance_id, action='START')

    def instance_shutdown(self, instance_id, wait=False):
        """Shutdown Compute Instance.

        Parameters:
            instance_id: the OCID of the instance
            wait: wait for completion (True/False)

        """
        self._echo_header('Shutdown initiated')
        if wait:
            compute_client_composite_operations = oci.core.ComputeClientCompositeOperations(self._compute_client)
            self._echo_message('Waiting for Stopped state', nl=False)
            compute_client_composite_operations.instance_action_and_wait_for_state(
                instance_id=instance_id,
                action='SOFTSTOP',
                wait_for_states=[oci.core.models.Instance.LIFECYCLE_STATE_STOPPED],
                waiter_kwargs={'wait_callback': self._wait_callback})
            self._echo()
        else:
            self._compute_client.instance_action(instance_id, action='SOFTSTOP')
