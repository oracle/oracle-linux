#!/usr/bin/env python3

"""
Generate OLVM compatible OVF file.

Copyright (c) 2020, 2022 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

from argparse import ArgumentDefaultsHelpFormatter, ArgumentParser
from datetime import datetime
from os import remove, stat
from os.path import isfile
from subprocess import call
import sys
from uuid import uuid4
from xml.dom.minidom import Document


# OLVM IDs for the 64 bits x86 OL platforms
OS_ID = {
    'OL5': 5001,
    'OL6': 5002,
    'OL7': 5003,
    'OL8': 5006,
    'OL9': 5006,  # Use OL8 ID for now, to support older OLVM versions
}


class OvfDocument(Document):
    """Add convenience method for element creation."""

    def createOvfElement(self,  # noqa: N802
                         name,
                         attr=None,
                         text=None,
                         parent=None,
                         text_elements=None):
        """Create element with optional attributes and text."""
        element = self.createElement(name)

        if parent:
            parent.appendChild(element)

        if attr:
            for key, value in attr.items():
                element.setAttribute(key, value)

        if text:
            element.appendChild(self.createTextNode(text))

        if text_elements:
            for key, value in text_elements.items():
                self.createOvfElement(key, parent=element, text=value)

        return element


def get_uuid():
    """Return UUID as a string."""
    return str(uuid4())


def parse_args():
    """Parse arguments."""
    parser = ArgumentParser(
        description='Generate an OLVM OVF and package in an OVA library.',
        formatter_class=ArgumentDefaultsHelpFormatter
    )
    parser.add_argument('-r',
                        '--release',
                        default='OL7',
                        help='Release')
    parser.add_argument('-u',
                        '--update',
                        required=True,
                        help='Update, e.g. 7')
    parser.add_argument('-v',
                        '--version',
                        default=0,
                        help='Build version, e.g. 2')
    parser.add_argument('-c',
                        '--cpu',
                        type=int,
                        default=1,
                        help='Number of VCPU')
    parser.add_argument('-m',
                        '--memory',
                        type=int,
                        default=1024,
                        help='Memory size in MB')
    parser.add_argument('-s',
                        '--size',
                        type=int,
                        required=True,
                        help='Image size in GB, e.g. 10')
    parser.add_argument('-i',
                        '--image',
                        default='System.qcow',
                        help='Image file name')
    parser.add_argument('-t',
                        '--template',
                        action='store_true',
                        help='Create a template')
    parser.add_argument('--script',
                        help='Cloud-init custom script')

    args = parser.parse_args()

    if not isfile(args.image):
        parser.error("Image file does not exists.")

    # Full build name
    args.build = '{0}U{1}_x86_64-olvm-b{2}'.format(args.release,
                                                   args.update,
                                                   args.version)

    return args


def generate_ovf(args):
    """Generate the OVF document."""
    # Image capacity and size on disk
    disk_capacity = args.size * 1024 * 1024 * 1024
    file_size = stat(args.image).st_size
    # The imported disk image will be an uncompressed qcow file
    uncompressed = args.image + ".uncompressed"
    call(["qemu-img", "convert", "-O", "qcow2", args.image, uncompressed])
    disk_size = stat(uncompressed).st_size
    remove(uncompressed)

    # Random UUIDs
    file_uuid = get_uuid()
    disk_uuid = get_uuid()
    ovf_uuid = get_uuid()

    # Timestamp for objects
    iso_time = datetime.utcnow().strftime("%Y/%m/%d %H:%M:%S")

    if args.release in OS_ID:
        os_id = OS_ID[args.release]
    else:
        print('Warning: unknown OS release {0}'.format(args.release), file=sys.stderr)
        os_id = 0

    document = OvfDocument()

    # Envelope
    namespaces = {
        'xmlns': 'http://schemas.dmtf.org/ovf/envelope/1',
        'xmlns:ovf': 'http://schemas.dmtf.org/ovf/envelope/1',
        'xmlns:rasd': ('http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/'
                       'CIM_ResourceAllocationSettingData'),
        'xmlns:vssd': ('http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/'
                       'CIM_VirtualSystemSettingData'),
        'xmlns:xsi': 'http://www.w3.org/2001/XMLSchema-instance',
        'xmlns:ovirt': 'http://www.ovirt.org/ovf',
    }
    envelope = document.createOvfElement('ovf:Envelope',
                                         parent=document,
                                         attr=namespaces
                                         )

    # Envelope / References
    reference = document.createOvfElement('References', parent=envelope)

    # Envelope / References / File
    document.createOvfElement('File', parent=reference, attr={
        # href is the actual file name on disk, it seems that oVirt expects to
        # have it equal to the id...
        'ovf:href': file_uuid,
        # Internal id
        'ovf:id': file_uuid,
        # Size on disk
        'ovf:size': str(file_size),
    })

    # Envelope / Network Section
    network_section = document.createOvfElement('NetworkSection',
                                                parent=envelope)
    document.createOvfElement('Info',
                              parent=network_section,
                              text='List of networks')
    document.createOvfElement('Network', parent=network_section, attr={
        'ovf:name': 'ovirtvm',
    })

    # Envelope / Disk Section
    disk_section = document.createOvfElement('DiskSection', parent=envelope)
    document.createOvfElement('Info',
                              parent=disk_section,
                              text='List of Virtual Disks')

    # Envelope / Disk Section / Disk
    document.createOvfElement('Disk', parent=disk_section, attr={
        # UUID for this disk
        'ovf:diskId': disk_uuid,
        # Image size
        'ovf:capacity': str(disk_capacity),
        # Size on disk of the uncompressed qcow file
        'ovf:populatedSize': str(disk_size),
        # Ref to file (should be the "id" of fileref)
        'ovf:fileRef': file_uuid,
        'ovf:parentRef': '',
        'ovf:format': 'http://www.gnome.org/~markmc/qcow-image-format.html',
        'ovf:volume-format': 'COW',
        'ovf:volume-type': 'Sparse',
        'ovf:disk-interface': 'VirtIO',
        'ovf:boot': 'true',
        'ovf:disk-type': 'System',
        'ovf:disk-alias': 'Disk_' + args.build,
    })

    # Envelope / Virtual System
    virtual_system = document.createOvfElement('VirtualSystem',
                                               parent=envelope,
                                               attr={
                                                   'ovf:id': ovf_uuid,
                                               })

    # Envelope / Virtual System / Text elements
    virtual_system_elements = {
        'Name': args.build,
        'Description': 'Generated by oracle-linux-image-tools',
        'Comment': '',
        'CreationDate': iso_time,
        'ExportDate': iso_time,
        'DeleteProtected': 'false',
        'NumOfIoThreads': '1',
        'TimeZone': 'Etc/GMT',
        'ClusterCompatibilityVersion': '4.2',
        # VmType 1 is server
        'VmType': '1',
        'ResumeBehavior': 'AUTO_RESUME',
        'MinAllocatedMem': str(args.memory),
        'IsStateless': 'false',
        'IsRunAndPause': 'false',
        'AutoStartup': 'false',
        'Priority': '1',
        'MigrationSupport': '0',
        'IsBootMenuEnabled': 'false',
        'IsSpiceFileTransferEnabled': 'true',
        'IsSpiceCopyPasteEnabled': 'true',
        'AllowConsoleReconnect': 'true',
        'ConsoleDisconnectAction': 'LOCK_SCREEN',
        'MaxMemorySizeMb': str(args.memory),
        'MultiQueuesEnabled': 'true',
        # Not sure about this one...
        'Origin': '0',
        # DefaultDisplayType 2 is VNC / 1 is QXL
        'DefaultDisplayType': '2',
        'TrustedService': 'false',
        'UseHostCpu': 'false',
    }
    if args.template:
        virtual_system_elements.update({
            'TemplateId': ovf_uuid,
            'TemplateType': 'TEMPLATE',
            'BaseTemplateId': ovf_uuid,
            'TemplateVersionNumber': '1',
            'TemplateVersionName': 'base version',
        })
    else:
        virtual_system_elements.update({
            'TemplateId': '00000000-0000-0000-0000-000000000000',
            'OriginalTemplateId': '00000000-0000-0000-0000-000000000000',
            'OriginalTemplateName': 'Blank',
            'UseLatestVersion': 'false',
            'StopTime': iso_time,
        })

    if args.script:
        document.createOvfElement('VmInit',
                                  parent=virtual_system,
                                  attr={
                                      'ovf:authorizedKeys': '',
                                      'ovf:regenerateKeys': 'false',
                                      'ovf:networks': '[ ]',
                                      'ovf:customScript': args.script.replace('\n', '&#10;'),
                                  })

    for key, value in virtual_system_elements.items():
        document.createOvfElement(key, parent=virtual_system, text=value)

    # Envelope / Virtual System / Operating System Section
    os_section = document.createOvfElement('OperatingSystemSection',
                                           parent=virtual_system,
                                           attr={
                                               # Perl has UUID
                                               'ovf:id': '1',
                                               # Should be 'ovirt:id', but
                                               # minidom does not handle
                                               # properly namespaces
                                               'ovirt:ovirt_id': str(os_id),
                                               'ovf:required': 'false',
                                           })

    # Envelope / Virtual System / Operating System Section / Info
    document.createOvfElement('Info',
                              parent=os_section,
                              text='Guest Operating System')

    # Envelope / Virtual System / Operating System Section / Description
    document.createOvfElement('Description',
                              parent=os_section,
                              text='{0}U{1} x64'.format(args.release,
                                                        args.update))

    # Envelope / Virtual System / Virtual Hardware Section
    vh_section = document.createOvfElement('VirtualHardwareSection',
                                           parent=virtual_system)

    # Envelope / Virtual System / Virtual Hardware Section / Info
    document.createOvfElement(
        'Info',
        parent=vh_section,
        text='{0} CPU, {1} Memory'.format(args.cpu, args.memory))

    # Envelope / Virtual System / Virtual Hardware Section / System
    document.createOvfElement('vssd:VirtualSystemType',
                              text='ENGINE 4.1.0.0',
                              parent=document.createOvfElement(
                                  'System',
                                  parent=vh_section))

    # Envelope / Virtual System / Virtual Hardware Section / Item CPU
    document.createOvfElement('Item', parent=vh_section, text_elements={
        'rasd:Caption': '{} virtual cpu'.format(args.cpu),
        'rasd:Description': 'Number of virtual CPU',
        'rasd:InstanceId': '1',
        'rasd:ResourceType': '3',
        'rasd:num_of_sockets': str(args.cpu),
        'rasd:cpu_per_socket': '1',
        'rasd:threads_per_cpu': '1',
        'rasd:max_num_of_vcpus': '16',
        'rasd:VirtualQuantity': str(args.cpu),
    })

    # Envelope / Virtual System / Virtual Hardware Section / Item Memory
    document.createOvfElement('Item', parent=vh_section, text_elements={
        'rasd:Caption': '{} MB of memory'.format(args.memory),
        'rasd:Description': 'Memory Size',
        'rasd:InstanceId': '2',
        'rasd:ResourceType': '4',
        'rasd:AllocationUnits': 'MegaBytes',
        'rasd:VirtualQuantity': str(args.memory),
    })

    # Envelope / Virtual System / Virtual Hardware Section / Item USB
    document.createOvfElement('Item', parent=vh_section, text_elements={
        'rasd:Caption': 'USB Controller',
        'rasd:InstanceId': '3',
        'rasd:ResourceType': '23',
        'rasd:UsbPolicy': 'DISABLED',
    })

    # Envelope / Virtual System / Virtual Hardware Section / Item Graphical
    # Controller
    document.createOvfElement('Item', parent=vh_section, text_elements={
        'rasd:Caption': 'Graphical Controller',
        'rasd:InstanceId': get_uuid(),
        'rasd:ResourceType': '32768',
        'Type': 'video',
        'rasd:VirtualQuantity': '1',
        'Device': 'vga',
    })

    # Envelope / Virtual System / Virtual Hardware Section / Item Disk Drive
    document.createOvfElement('Item', parent=vh_section, text_elements={
        'rasd:Caption': 'Drive: 1',
        'rasd:InstanceId': file_uuid,
        'rasd:ResourceType': '17',
        'Type': 'disk',
        'rasd:HostResource': 'ovf:disk/' + disk_uuid,
        'rasd:Parent': '00000000-0000-0000-0000-000000000000',
        'rasd:Template': '00000000-0000-0000-0000-000000000000',
        'rasd:ApplicationList': '',
        'rasd:StorageId': '00000000-0000-0000-0000-000000000000',
        'rasd:StoragePoolId': '00000000-0000-0000-0000-000000000000',
        'rasd:CreationDate': iso_time,
        'rasd:LastModified': iso_time,
        'rasd:last_modified_date': iso_time,
        'Device': 'disk',
        'BootOrder': '0',
        'IsPlugged': 'true',
        'IsReadOnly': 'false',
    })

    # Envelope / Virtual System / Virtual Hardware Section / Item Network
    document.createOvfElement('Item', parent=vh_section, text_elements={
        'rasd:Caption': 'Ethernet adapter on ovirtvm',
        'rasd:InstanceId': get_uuid(),
        'rasd:ResourceType': '10',
        'rasd:OtherResourceType': 'ovirtvm',
        'rasd:ResourceSubType': '3',
        'rasd:Connection': 'ovirtvm',
        'rasd:Linked': 'true',
        'rasd:Name': 'nic1',
        'rasd:ElementName': 'nic1',
        'rasd:speed': '10000',
        'Type': 'interface',
        'Device': 'bridge',
        'BootOrder': '0',
        'IsPlugged': 'true',
        'IsReadOnly': 'false',
    })

    ovf = document.toprettyxml(indent='  ', encoding='UTF-8')
    # Fixup for namespace
    ovf = ovf.replace(b'ovirt:ovirt_id', b'ovirt:id')
    # Fixup for &#10;
    ovf = ovf.replace(b'&amp;#10;', b'&#10;')
    return ovf.decode()


def main():
    """Make envelope."""
    args = parse_args()
    print(generate_ovf(args), end="")


if __name__ == '__main__':
    main()
