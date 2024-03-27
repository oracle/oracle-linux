#!/usr/bin/env python3

"""
Generate VirtualBox OVF file.

Copyright (c) 2020, 2024 Oracle and/or its affiliates.
Licensed under the Universal Permissive License v 1.0 as shown at
https://oss.oracle.com/licenses/upl

DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS HEADER.
"""

import argparse
from datetime import datetime, timezone
import os.path
import random
import uuid
from xml.dom.minidom import Document

# OS Id and type
OS_ID = 109  # 109 is OL
OS_TYPE = "Oracle_64"


class OvfDocument(Document):
    """Add convenience method for element creation."""

    def createOvfElement(
        self, name, attr=None, text=None, parent=None, text_elements=None  # noqa: N802
    ):
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
    return str(uuid.uuid4())


def parse_args():
    """Parse arguments."""
    parser = argparse.ArgumentParser(
        description="Generate an OLVM OVF and package in an OVA library.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("-n", "--name", required=True, help="Image name")
    parser.add_argument("-c", "--cpu", type=int, default=1, help="Number of VCPU")
    parser.add_argument(
        "-m", "--memory", type=int, default=1024, help="Memory size in MB"
    )
    parser.add_argument("-i", "--image", required=True, help="Image file name")
    parser.add_argument(
        "-s", "--size", type=int, required=True, help="Image size in GB, e.g. 10"
    )
    parser.add_argument("--extra-image", help="Optional extra image file name")
    parser.add_argument(
        "--extra-size", type=int, help="Optional extra image size in GB, e.g. 10"
    )

    args = parser.parse_args()

    if not os.path.isfile(args.image):
        parser.error("Image file does not exists.")

    if (args.extra_image and not args.extra_size) or (not args.extra_image and  args.extra_size):
        parser.error("Extra image and extra size must both specify or omitted")
    if args.extra_image and not os.path.isfile(args.extra_image):
        parser.error("Extra image file does not exists.")

    return args


def generate_ovf(args):
    """Generate the OVF document."""
    # Image capacity and size on disk
    disk_capacity = args.size * 1024 * 1024 * 1024

    # Random UUIDs
    disk_uuid = get_uuid()
    extra_disk_uuid = get_uuid()
    machine_uuid = get_uuid()
    mac_address = "080027{:02x}{:02x}{:02x}".format(
        random.randint(0, 0xFF), random.randint(0, 0xFF), random.randint(0, 0xFF)
    )
    # Timestamp for objects
    iso_time = (
        datetime.now(tz=timezone.utc)
        .isoformat(timespec="seconds")
        .replace("+00:00", "Z")
    )

    # Files/disks references
    file_ref = "file"
    disk_id = "vmdisk"

    document = OvfDocument()

    # Envelope
    namespaces = {
        "xmlns": "http://schemas.dmtf.org/ovf/envelope/1",
        "xmlns:ovf": "http://schemas.dmtf.org/ovf/envelope/1",
        "xmlns:rasd": (
            "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/"
            "CIM_ResourceAllocationSettingData"
        ),
        "xmlns:vssd": (
            "http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/"
            "CIM_VirtualSystemSettingData"
        ),
        "xmlns:xsi": "http://www.w3.org/2001/XMLSchema-instance",
        "xmlns:vbox": "http://www.virtualbox.org/ovf/machine",
    }
    envelope = document.createOvfElement(
        "Envelope",
        parent=document,
        attr={
            "ovf:version": "1.0",
            "xml:lang": "en-US",
            **namespaces,
        },
    )

    # Envelope / References
    reference = document.createOvfElement("References", parent=envelope)

    # Envelope / References / File
    document.createOvfElement(
        "File",
        parent=reference,
        attr={
            "ovf:id": f"{file_ref}1",
            "ovf:href": os.path.basename(args.image),
        },
    )
    if args.extra_image:
        document.createOvfElement(
            "File",
            parent=reference,
            attr={
                "ovf:id": f"{file_ref}2",
                "ovf:href": os.path.basename(args.extra_image),
            },
        )

    # Envelope / Disk Section
    disk_section = document.createOvfElement("DiskSection", parent=envelope)
    document.createOvfElement(
        "Info",
        parent=disk_section,
        text="List of the virtual disks used in the package",
    )

    # Envelope / Disk Section / Disk
    document.createOvfElement(
        "Disk",
        parent=disk_section,
        attr={
            # Image size
            "ovf:capacity": str(disk_capacity),
            # UUID for this disk
            "ovf:diskId": f"{disk_id}1",
            # Ref to file (should be the "id" of fileref)
            "ovf:fileRef": f"{file_ref}1",
            "ovf:format": "http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized",
            "vbox:uuid": disk_uuid,
        },
    )
    if args.extra_image:
        document.createOvfElement(
            "Disk",
            parent=disk_section,
            attr={
                # Image size
                "ovf:capacity": str(disk_capacity),
                # UUID for this disk
                "ovf:diskId": f"{disk_id}2",
                # Ref to file (should be the "id" of fileref)
                "ovf:fileRef": f"{file_ref}2",
                "ovf:format": "http://www.vmware.com/interfaces/specifications/vmdk.html",
                "vbox:uuid": extra_disk_uuid,
            },
        )

    # Envelope / Network Section
    network_section = document.createOvfElement("NetworkSection", parent=envelope)
    document.createOvfElement(
        "Info", parent=network_section, text="Logical networks used in the package"
    )
    document.createOvfElement(
        "Network",
        parent=network_section,
        attr={
            "ovf:name": "NAT",
        },
        text_elements={"Description": "Logical network used by this appliance."},
    )

    # Envelope / Virtual System
    virtual_system = document.createOvfElement(
        "VirtualSystem",
        parent=envelope,
        attr={
            "ovf:id": args.name,
        },
    )
    document.createOvfElement("Info", parent=virtual_system, text="A virtual machine")

    # Envelope / Virtual System / Operating System Section
    os_section = document.createOvfElement(
        "OperatingSystemSection",
        parent=virtual_system,
        attr={
            "ovf:id": str(OS_ID),
        },
    )

    # Envelope / Virtual System / Operating System Section / Info
    document.createOvfElement(
        "Info", parent=os_section, text="The kind of installed guest operating system"
    )

    # Envelope / Virtual System / Operating System Section / Description
    document.createOvfElement(
        "Description",
        parent=os_section,
        text=OS_TYPE,
    )

    # Envelope / Virtual System / Operating System Section / OSType
    document.createOvfElement(
        "vbox:OSType",
        parent=os_section,
        attr={
            "ovf:required": "false",
        },
        text=OS_TYPE,
    )

    # Envelope / Virtual System / Virtual Hardware Section
    vh_section = document.createOvfElement(
        "VirtualHardwareSection", parent=virtual_system
    )

    # Envelope / Virtual System / Virtual Hardware Section / Info
    document.createOvfElement(
        "Info",
        parent=vh_section,
        text="Virtual hardware requirements for a virtual machine",
    )

    # Envelope / Virtual System / Virtual Hardware Section / System
    document.createOvfElement(
        "System",
        parent=vh_section,
        text_elements={
            "vssd:ElementName": "Virtual Hardware Family",
            "vssd:InstanceID": "0",
            "vssd:VirtualSystemIdentifier": args.name,
            "vssd:VirtualSystemType": "virtualbox-2.2",
        },
    )

    # Envelope / Virtual System / Virtual Hardware Section / Item CPU
    instance_id = 1
    document.createOvfElement(
        "Item",
        parent=vh_section,
        text_elements={
            "rasd:Caption": "{} virtual CPU".format(args.cpu),
            "rasd:Description": "Number of virtual CPUs",
            "rasd:ElementName": "{} virtual CPU".format(args.cpu),
            "rasd:InstanceID": str(instance_id),
            "rasd:ResourceType": "3",
            "rasd:VirtualQuantity": str(args.cpu),
        },
    )

    # Envelope / Virtual System / Virtual Hardware Section / Item Memory
    instance_id += 1
    document.createOvfElement(
        "Item",
        parent=vh_section,
        text_elements={
            "rasd:AllocationUnits": "MegaBytes",
            "rasd:Caption": "{} MB of memory".format(args.memory),
            "rasd:Description": "Memory Size",
            "rasd:ElementName": "{} MB of memory".format(args.memory),
            "rasd:InstanceID": str(instance_id),
            "rasd:ResourceType": "4",
            "rasd:VirtualQuantity": str(args.memory),
        },
    )

    # Envelope / Virtual System / Virtual Hardware Section / IDE Controller 0
    instance_id += 1
    document.createOvfElement(
        "Item",
        parent=vh_section,
        text_elements={
            "rasd:Address": "0",
            "rasd:Caption": "ideController0",
            "rasd:Description": "IDE Controller",
            "rasd:ElementName": "ideController0",
            "rasd:InstanceID": str(instance_id),
            "rasd:ResourceSubType": "PIIX4",
            "rasd:ResourceType": "5",
        },
    )

    # Envelope / Virtual System / Virtual Hardware Section / IDE Controller 1
    instance_id += 1
    document.createOvfElement(
        "Item",
        parent=vh_section,
        text_elements={
            "rasd:Address": "1",
            "rasd:Caption": "ideController1",
            "rasd:Description": "IDE Controller",
            "rasd:ElementName": "ideController1",
            "rasd:InstanceID": str(instance_id),
            "rasd:ResourceSubType": "PIIX4",
            "rasd:ResourceType": "5",
        },
    )

    # Envelope / Virtual System / Virtual Hardware Section / SATA Controller 0
    instance_id += 1
    document.createOvfElement(
        "Item",
        parent=vh_section,
        text_elements={
            "rasd:Address": "0",
            "rasd:Caption": "sataController0",
            "rasd:Description": "SATA Controller",
            "rasd:ElementName": "sataController0",
            "rasd:InstanceID": str(instance_id),
            "rasd:ResourceSubType": "AHCI",
            "rasd:ResourceType": "20",
        },
    )

    # Envelope / Virtual System / Virtual Hardware Section / Disk
    instance_id += 1
    document.createOvfElement(
        "Item",
        parent=vh_section,
        text_elements={
            "rasd:AddressOnParent": "0",
            "rasd:Caption": "disk1",
            "rasd:Description": "Disk Image",
            "rasd:ElementName": "disk1",
            "rasd:HostResource": f"/disk/{disk_id}1",
            "rasd:InstanceID": str(instance_id),
            "rasd:Parent": "5",
            "rasd:ResourceType": "17",
        },
    )
    if args.extra_image:
        instance_id += 1
        document.createOvfElement(
            "Item",
            parent=vh_section,
            text_elements={
                "rasd:AddressOnParent": "1",
                "rasd:Caption": "disk2",
                "rasd:Description": "Disk Image",
                "rasd:ElementName": "disk2",
                "rasd:HostResource": f"/disk/{disk_id}2",
            "rasd:InstanceID": str(instance_id),
                "rasd:Parent": "5",
                "rasd:ResourceType": "17",
            },
        )

    # Envelope / Virtual System / Virtual Hardware Section / Item Network
    instance_id += 1
    document.createOvfElement(
        "Item",
        parent=vh_section,
        text_elements={
            "rasd:AutomaticAllocation": "true",
            "rasd:Caption": "Ethernet adapter on 'NAT'",
            "rasd:Connection": "NAT",
            "rasd:ElementName": "Ethernet adapter on 'NAT'",
            "rasd:InstanceID": str(instance_id),
            "rasd:ResourceType": "10",
        },
    )

    # Envelope / Virtual System / Machine Section
    machine_section = document.createOvfElement(
        "vbox:Machine",
        parent=virtual_system,
        attr={
            "ovf:required": "false",
            "version": "1.19-linux",
            "uuid": f"{{{machine_uuid}}}",
            "name": args.name,
            "OSType": OS_TYPE,
            "snapshotFolder": "Snapshots",
            "lastStateChange": iso_time,
        },
    )

    # Envelope / Virtual System / Machine Section / Info
    document.createOvfElement(
        "ovf:Info",
        parent=machine_section,
        text="Complete VirtualBox machine configuration in VirtualBox format",
    )

    # Envelope / Virtual System / Machine Section / Hardware
    ms_hardware = document.createOvfElement(
        "Hardware",
        parent=machine_section,
    )

    ms_hardware_cpu = document.createOvfElement(
        "CPU", parent=ms_hardware, attr={"count": str(args.cpu)}
    )
    document.createOvfElement("PAE", parent=ms_hardware_cpu, attr={"enabled": "true"})
    document.createOvfElement(
        "LongMode", parent=ms_hardware_cpu, attr={"enabled": "true"}
    )
    document.createOvfElement(
        "X2APIC", parent=ms_hardware_cpu, attr={"enabled": "true"}
    )
    document.createOvfElement(
        "HardwareVirtExLargePages", parent=ms_hardware_cpu, attr={"enabled": "true"}
    )

    document.createOvfElement(
        "Memory", parent=ms_hardware, attr={"RAMSize": str(args.memory)}
    )

    ms_hardware_boot = document.createOvfElement("Boot", parent=ms_hardware)
    document.createOvfElement(
        "Order", parent=ms_hardware_boot, attr={"position": "1", "device": "HardDisk"}
    )
    document.createOvfElement(
        "Order", parent=ms_hardware_boot, attr={"position": "2", "device": "DVD"}
    )
    document.createOvfElement(
        "Order", parent=ms_hardware_boot, attr={"position": "3", "device": "None"}
    )
    document.createOvfElement(
        "Order", parent=ms_hardware_boot, attr={"position": "4", "device": "None"}
    )

    document.createOvfElement("Display", parent=ms_hardware, attr={"VRAMSize": "4"})

    ms_hardware_rd = document.createOvfElement(
        "RemoteDisplay", parent=ms_hardware, attr={"enabled": "true"}
    )
    ms_hardware_rd_vrde = document.createOvfElement(
        "VRDEProperties", parent=ms_hardware_rd
    )
    document.createOvfElement(
        "Property",
        parent=ms_hardware_rd_vrde,
        attr={"name": "TCP/Address", "value": "127.0.0.1"},
    )
    document.createOvfElement(
        "Property",
        parent=ms_hardware_rd_vrde,
        attr={"name": "TCP/Ports", "value": "5905"},
    )

    ms_hardware_bios = document.createOvfElement("BIOS", parent=ms_hardware)
    document.createOvfElement(
        "IOAPIC", parent=ms_hardware_bios, attr={"enabled": "true"}
    )
    document.createOvfElement(
        "SmbiosUuidLittleEndian", parent=ms_hardware_bios, attr={"enabled": "true"}
    )

    document.createOvfElement(
        "NAT",
        attr={"localhost-reachable": "true"},
        parent=document.createOvfElement(
            "Adapter",
            attr={
                "slot": "0",
                "enabled": "true",
                "MACAddress": mac_address,
                "type": "virtio",
            },
            parent=document.createOvfElement("Network", parent=ms_hardware),
        ),
    )

    document.createOvfElement(
        "AudioAdapter", parent=ms_hardware, attr={"driver": "Null"}
    )

    document.createOvfElement("Clipboard", parent=ms_hardware)

    ms_hardware_storage = document.createOvfElement(
        "StorageControllers", parent=ms_hardware
    )
    document.createOvfElement(
        "StorageController",
        parent=ms_hardware_storage,
        attr={
            "name": "IDE Controller",
            "type": "PIIX4",
            "PortCount": "2",
            "useHostIOCache": "true",
            "Bootable": "true",
        },
    )
    ms_hardware_storage_sata = document.createOvfElement(
        "StorageController",
        parent=ms_hardware_storage,
        attr={
            "name": "SATA Controller",
            "type": "AHCI",
            "PortCount": "2" if args.extra_image else "1",
            "useHostIOCache": "false",
            "Bootable": "true",
            "IDE0MasterEmulationPort": "0",
            "IDE0SlaveEmulationPort": "1",
            "IDE1MasterEmulationPort": "2",
            "IDE1SlaveEmulationPort": "3",
        },
    )
    document.createOvfElement(
        "Image",
        attr={"uuid": f"{{{disk_uuid}}}"},
        parent=document.createOvfElement(
            "AttachedDevice",
            attr={
                "type": "HardDisk",
                "hotpluggable": "false",
                "port": "0",
                "device": "0",
            },
            parent=ms_hardware_storage_sata,
        ),
    )
    if args.extra_image:
        document.createOvfElement(
            "Image",
            attr={"uuid": f"{{{extra_disk_uuid}}}"},
            parent=document.createOvfElement(
                "AttachedDevice",
                attr={
                    "type": "HardDisk",
                    "hotpluggable": "false",
                    "port": "1",
                    "device": "0",
                },
                parent=ms_hardware_storage_sata,
            ),
        )

    return document.toprettyxml(indent="  ")


def main():
    """Make envelope."""
    args = parse_args()
    print(generate_ovf(args), end="")


if __name__ == "__main__":
    main()
