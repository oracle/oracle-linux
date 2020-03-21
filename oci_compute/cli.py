"""OCI Compute CLI.

Provides the command line interface for the oci-infra script.

Copyright (c) 1982-2020 Oracle and/or its affiliates. All rights reserved.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl.

SPDX-License-Identifier: UPL-1.0
"""
from os.path import expanduser, expandvars

import click
from terminaltables import AsciiTable

from .oci_compute import OciCompute
from .rc_file import RcFile

# Parameters default values
CONFIG_FILE = '~/.oci/config'
PROFILE = 'DEFAULT'
RC_FILE = '~/.oci/oci_compute_rc'


class ExpandedPath(click.ParamType):
    """Path checking after expansion.

    The click Path type assumes expansion is done by the shell, but we also
    want to handle default values (constants or from the rc file).
    """

    name = 'path'

    def convert(self, value, param, ctx):
        path = expandvars(expanduser(value))
        try:
            with open(path) as fp:  # noqa: F841
                pass
        except:  # noqa: E722
            self.fail('Cannot open {0} for reading'.format(value), param, ctx)

        return path


def get_default_rc(variable):
    """Return default value for an rc file variable.

    Simple helper for readability.
    """
    return click.get_current_context().obj['rc_file'].get_default_rc(variable)


@click.group()
@click.version_option()
@click.option(
    '-v',
    '--verbose',
    is_flag=True,
    help='Verbose mode'
)
@click.option(
    '--config-file',
    default=CONFIG_FILE,
    show_default=True,
    type=ExpandedPath(),
    help='The path to the config file.',
)
@click.option(
    '--profile',
    default=PROFILE,
    show_default=True,
    help='The profile in the config file to load.',
)
@click.option(
    '--rc-file',
    default=RC_FILE,
    show_default=True,
    type=ExpandedPath(),
    help='The path to the OCI Provision specific configuration file',
)
@click.pass_context
def cli(ctx, verbose, config_file, profile, rc_file):
    """Oracle Cloud Infrastructure Python SDK demo."""
    ctx.ensure_object(dict)
    ctx.obj['rc_file'] = RcFile(rc_file, profile)
    try:
        ctx.obj['oci'] = OciCompute(config_file=config_file,
                                    profile=profile,
                                    verbose=verbose)
    except Exception as e:
        click.echo('Could not get configuration: {}'.format(e), err=True)
        ctx.exit(1)


@click.option(
    '--compartment-id',
    default=lambda: get_default_rc('compartment-id'),
    show_default=RcFile.get_default('compartment-id'),
    required=True,
    help='The OCID of the compartment',
)
@cli.command(
    name='list-platform',
    help='List Platform Images',
)
@click.pass_context
def list_platform(ctx, compartment_id):
    oci = ctx.obj['oci']
    images = oci.list_platform(compartment_id)
    if images:
        table = AsciiTable(
            [('Operating System', 'Operating System version')] + images)
        table.title = 'Platform images'
        click.echo(table.table)
    else:
        click.echo('No image found', err=True)


@click.option(
    '--compartment-id',
    default=lambda: get_default_rc('compartment-id'),
    show_default=RcFile.get_default('compartment-id'),
    required=True,
    help='The OCID of the compartment',
)
@cli.command(
    name='list-custom',
    help='List Custom Images',
)
@click.pass_context
def list_custom(ctx, compartment_id):
    oci = ctx.obj['oci']
    images = oci.list_custom(compartment_id)
    if images:
        table = AsciiTable(
            [('Display name', 'Time created')] + images)
        table.title = 'Custom images'
        click.echo(table.table)
    else:
        click.echo('No image found', err=True)


@cli.command(
    name='list-market',
    help='List free Marketplace Images',
)
@click.pass_context
def list_market(ctx):
    oci = ctx.obj['oci']
    listings = oci.list_market()
    if listings:
        table = AsciiTable(
            [('Publisher', 'Name')] + listings)
        table.title = 'Free Marketplace images'
        click.echo(table.table)
    else:
        click.echo('No image found', err=True)


@click.option(
    '--cloud-init-file',
    default=lambda: get_default_rc('cloud-init-file'),
    show_default=RcFile.get_default('cloud-init-file'),
    type=ExpandedPath(),
    help='A file that will be used by Cloud-init',
)
@click.option(
    '--ssh-authorized-keys-file',
    default=lambda: get_default_rc('ssh-authorized-keys-file'),
    show_default=RcFile.get_default('ssh-authorized-keys-file'),
    required=True,
    type=ExpandedPath(),
    help='A file containing one or more public SSH keys to access the instance',
)
@click.option(
    '--subnet-name',
    default=lambda: get_default_rc('subnet-name'),
    show_default=RcFile.get_default('subnet-name'),
    required=True,
    help='The subnet where the VNIC attached to this instance will be created',
)
@click.option(
    '--vcn-name',
    default=lambda: get_default_rc('vcn-name'),
    show_default=RcFile.get_default('vcn-name'),
    required=True,
    help='The VCN attached to this instance',
)
@click.option(
    '--availability-domain',
    default=lambda: get_default_rc('availability-domain'),
    show_default=RcFile.get_default('availability-domain'),
    required=True,
    help='The availability domain of the instance',
)
@click.option(
    '--shape',
    default=lambda: get_default_rc('shape'),
    show_default=RcFile.get_default('shape'),
    required=True,
    help='The shape of the instance',
)
@click.option(
    '--operating-system-version',
    default=lambda: get_default_rc('operating-system-version'),
    show_default=RcFile.get_default('operating-system-version'),
    required=True,
    help="The image's operating system version",
)
@click.option(
    '--operating-system',
    default=lambda: get_default_rc('operating-system'),
    show_default=RcFile.get_default('operating-system'),
    required=True,
    help="The image's operating system",
)
@click.option(
    '--compartment-id',
    default=lambda: get_default_rc('compartment-id'),
    show_default=RcFile.get_default('compartment-id'),
    required=True,
    help='The OCID of the compartment',
)
@click.option(
    '--display-name',
    default=lambda: get_default_rc('display-name'),
    show_default=RcFile.get_default('display-name'),
    required=True,
    help='The display name of the created image',
)
@cli.command(
    name='provision-platform',
    help='Provision a Platform Image'
)
@click.pass_context
def provision_platform(ctx,
                       display_name,
                       compartment_id,
                       operating_system,
                       operating_system_version,
                       shape,
                       availability_domain,
                       vcn_name,
                       subnet_name,
                       ssh_authorized_keys_file,
                       cloud_init_file):
    oci = ctx.obj['oci']
    instance = oci.provision_platform(display_name,
                                      compartment_id,
                                      operating_system,
                                      operating_system_version,
                                      shape,
                                      availability_domain,
                                      vcn_name,
                                      subnet_name,
                                      ssh_authorized_keys_file,
                                      cloud_init_file)
    if not instance:
        ctx.exit(1)

    vnic = oci.get_vnic(compartment_id, instance)
    if not vnic:
        ctx.exit(1)

    table = AsciiTable((('Private IP', vnic.private_ip),
                        ('Public IP', vnic.public_ip)))
    table.inner_heading_row_border = False
    table.title = 'Instance provisioned'
    click.echo(table.table)


@click.option(
    '--cloud-init-file',
    default=lambda: get_default_rc('cloud-init-file'),
    show_default=RcFile.get_default('cloud-init-file'),
    type=ExpandedPath(),
    help='A file that will be used by Cloud-init',
)
@click.option(
    '--ssh-authorized-keys-file',
    default=lambda: get_default_rc('ssh-authorized-keys-file'),
    show_default=RcFile.get_default('ssh-authorized-keys-file'),
    required=True,
    type=ExpandedPath(),
    help='A file containing one or more public SSH keys to access the instance',
)
@click.option(
    '--subnet-name',
    default=lambda: get_default_rc('subnet-name'),
    show_default=RcFile.get_default('subnet-name'),
    required=True,
    help='The subnet where the VNIC attached to this instance will be created',
)
@click.option(
    '--vcn-name',
    default=lambda: get_default_rc('vcn-name'),
    show_default=RcFile.get_default('vcn-name'),
    required=True,
    help='The VCN attached to this instance',
)
@click.option(
    '--availability-domain',
    default=lambda: get_default_rc('availability-domain'),
    show_default=RcFile.get_default('availability-domain'),
    required=True,
    help='The availability domain of the instance',
)
@click.option(
    '--shape',
    default=lambda: get_default_rc('shape'),
    show_default=RcFile.get_default('shape'),
    required=True,
    help='The shape of the instance',
)
@click.option(
    '--custom-image-name',
    default=lambda: get_default_rc('custom-image-name'),
    show_default=RcFile.get_default('custom-image-name'),
    required=True,
    help="The custom image name",
)
@click.option(
    '--compartment-id',
    default=lambda: get_default_rc('compartment-id'),
    show_default=RcFile.get_default('compartment-id'),
    required=True,
    help='The OCID of the compartment',
)
@click.option(
    '--display-name',
    default=lambda: get_default_rc('display-name'),
    show_default=RcFile.get_default('display-name'),
    required=True,
    help='The display name of the created image (case sensitive pattern matching)',
)
@cli.command(
    name='provision-custom',
    help='Provision a Custom Image',
)
@click.pass_context
def provision_custom(ctx,
                     display_name,
                     compartment_id,
                     custom_image_name,
                     shape,
                     availability_domain,
                     vcn_name,
                     subnet_name,
                     ssh_authorized_keys_file,
                     cloud_init_file):
    oci = ctx.obj['oci']
    instance = oci.provision_custom(display_name,
                                    compartment_id,
                                    custom_image_name,
                                    shape,
                                    availability_domain,
                                    vcn_name,
                                    subnet_name,
                                    ssh_authorized_keys_file,
                                    cloud_init_file)
    if not instance:
        ctx.exit(1)

    vnic = oci.get_vnic(compartment_id, instance)
    if not vnic:
        ctx.exit(1)

    table = AsciiTable((('Private IP', vnic.private_ip),
                        ('Public IP', vnic.public_ip)))
    table.inner_heading_row_border = False
    table.title = 'Instance provisioned'
    click.echo(table.table)


@click.option(
    '--cloud-init-file',
    default=lambda: get_default_rc('cloud-init-file'),
    show_default=RcFile.get_default('cloud-init-file'),
    type=ExpandedPath(),
    help='A file that will be used by Cloud-init',
)
@click.option(
    '--ssh-authorized-keys-file',
    default=lambda: get_default_rc('ssh-authorized-keys-file'),
    show_default=RcFile.get_default('ssh-authorized-keys-file'),
    required=True,
    type=ExpandedPath(),
    help='A file containing one or more public SSH keys to access the instance',
)
@click.option(
    '--subnet-name',
    default=lambda: get_default_rc('subnet-name'),
    show_default=RcFile.get_default('subnet-name'),
    required=True,
    help='The subnet where the VNIC attached to this instance will be created',
)
@click.option(
    '--vcn-name',
    default=lambda: get_default_rc('vcn-name'),
    show_default=RcFile.get_default('vcn-name'),
    required=True,
    help='The VCN attached to this instance',
)
@click.option(
    '--availability-domain',
    default=lambda: get_default_rc('availability-domain'),
    show_default=RcFile.get_default('availability-domain'),
    required=True,
    help='The availability domain of the instance',
)
@click.option(
    '--shape',
    default=lambda: get_default_rc('shape'),
    show_default=RcFile.get_default('shape'),
    required=True,
    help='The shape of the instance',
)
@click.option(
    '--market-image-name',
    default=lambda: get_default_rc('market-image-name'),
    show_default=RcFile.get_default('market-image-name'),
    required=True,
    help="The marketplace image name",
)
@click.option(
    '--compartment-id',
    default=lambda: get_default_rc('compartment-id'),
    show_default=RcFile.get_default('compartment-id'),
    required=True,
    help='The OCID of the compartment',
)
@click.option(
    '--display-name',
    default=lambda: get_default_rc('display-name'),
    show_default=RcFile.get_default('display-name'),
    required=True,
    help='The display name of the created image (case sensitive pattern matching)',
)
@cli.command(
    name='provision-market',
    help='Provision a free Martketplace Image',
)
@click.pass_context
def provision_market(ctx,
                     display_name,
                     compartment_id,
                     market_image_name,
                     shape,
                     availability_domain,
                     vcn_name,
                     subnet_name,
                     ssh_authorized_keys_file,
                     cloud_init_file):
    oci = ctx.obj['oci']
    instance = oci.provision_market(display_name,
                                    compartment_id,
                                    market_image_name,
                                    shape,
                                    availability_domain,
                                    vcn_name,
                                    subnet_name,
                                    ssh_authorized_keys_file,
                                    cloud_init_file)
    if not instance:
        ctx.exit(1)

    vnic = oci.get_vnic(compartment_id, instance)
    if not vnic:
        ctx.exit(1)

    table = AsciiTable((('Private IP', vnic.private_ip),
                        ('Public IP', vnic.public_ip)))
    table.inner_heading_row_border = False
    table.title = 'Instance provisioned'
    click.echo(table.table)


if __name__ == '__main__':
    cli()
