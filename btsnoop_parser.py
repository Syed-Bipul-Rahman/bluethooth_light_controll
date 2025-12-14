#!/usr/bin/env python3
"""
Simple btsnoop_hci.log Parser
Extracts: Connection requests, Disconnection events, Advertisement packets, GATT reads/writes
"""

import struct
from datetime import datetime, timedelta
from dataclasses import dataclass
from typing import List, Optional
import sys


# btsnoop file header constants
BTSNOOP_MAGIC = b'btsnoop\x00'
BTSNOOP_VERSION = 1
DATALINK_HCI = 1002

# HCI packet types
HCI_COMMAND = 0x01
HCI_ACL_DATA = 0x02
HCI_SCO_DATA = 0x03
HCI_EVENT = 0x04

# HCI Event codes
EVT_CONNECTION_COMPLETE = 0x03
EVT_CONNECTION_REQUEST = 0x04
EVT_DISCONNECTION_COMPLETE = 0x05
EVT_LE_META = 0x3E

# LE Meta subevent codes
LE_CONNECTION_COMPLETE = 0x01
LE_ADV_REPORT = 0x02
LE_CONNECTION_UPDATE_COMPLETE = 0x03
LE_ENHANCED_CONNECTION_COMPLETE = 0x0A
LE_EXT_ADV_REPORT = 0x0D

# HCI Command opcodes (OGF << 10 | OCF)
CMD_CREATE_CONNECTION = 0x0405
CMD_DISCONNECT = 0x0406
CMD_LE_CREATE_CONNECTION = 0x200D

# ATT opcodes for GATT
ATT_READ_REQ = 0x0A
ATT_READ_RSP = 0x0B
ATT_READ_BY_TYPE_REQ = 0x08
ATT_READ_BY_TYPE_RSP = 0x09
ATT_READ_BY_GROUP_REQ = 0x10
ATT_READ_BY_GROUP_RSP = 0x11
ATT_WRITE_REQ = 0x12
ATT_WRITE_RSP = 0x13
ATT_WRITE_CMD = 0x52
ATT_PREPARE_WRITE_REQ = 0x16
ATT_PREPARE_WRITE_RSP = 0x17
ATT_EXECUTE_WRITE_REQ = 0x18
ATT_EXECUTE_WRITE_RSP = 0x19

# L2CAP CID for ATT
L2CAP_CID_ATT = 0x0004


@dataclass
class BtsnoopPacket:
    """Represents a single btsnoop packet record"""
    timestamp: datetime
    direction: str  # 'sent' or 'received'
    packet_type: int
    data: bytes


@dataclass
class ConnectionRequest:
    timestamp: datetime
    direction: str
    bd_addr: str
    link_type: str
    event_type: str  # 'request', 'complete', 'le_create'


@dataclass
class DisconnectionEvent:
    timestamp: datetime
    handle: int
    reason: int
    reason_str: str


@dataclass
class AdvertisementPacket:
    timestamp: datetime
    event_type: int
    addr_type: str
    bd_addr: str
    rssi: int
    data: bytes


@dataclass
class GattOperation:
    timestamp: datetime
    direction: str
    operation: str
    handle: Optional[int]
    data: bytes


class BtsnoopParser:
    """Parser for btsnoop_hci.log files"""

    # btsnoop epoch: midnight, January 1st, 0 AD
    BTSNOOP_EPOCH = datetime(1, 1, 1)

    DISCONNECT_REASONS = {
        0x00: "Success",
        0x05: "Authentication Failure",
        0x06: "PIN or Key Missing",
        0x07: "Memory Capacity Exceeded",
        0x08: "Connection Timeout",
        0x09: "Connection Limit Exceeded",
        0x0C: "Command Disallowed",
        0x13: "Remote User Terminated Connection",
        0x14: "Remote Device Terminated due to Low Resources",
        0x15: "Remote Device Terminated due to Power Off",
        0x16: "Connection Terminated by Local Host",
        0x1A: "Unsupported Remote Feature",
        0x22: "LMP Response Timeout",
        0x3E: "Connection Failed to be Established",
    }

    ADV_TYPES = {
        0x00: "ADV_IND",
        0x01: "ADV_DIRECT_IND",
        0x02: "ADV_SCAN_IND",
        0x03: "ADV_NONCONN_IND",
        0x04: "SCAN_RSP",
    }

    ADDR_TYPES = {
        0x00: "Public",
        0x01: "Random",
        0x02: "Public Identity",
        0x03: "Random Identity",
    }

    ATT_OPCODES = {
        ATT_READ_REQ: "Read Request",
        ATT_READ_RSP: "Read Response",
        ATT_READ_BY_TYPE_REQ: "Read By Type Request",
        ATT_READ_BY_TYPE_RSP: "Read By Type Response",
        ATT_READ_BY_GROUP_REQ: "Read By Group Type Request",
        ATT_READ_BY_GROUP_RSP: "Read By Group Type Response",
        ATT_WRITE_REQ: "Write Request",
        ATT_WRITE_RSP: "Write Response",
        ATT_WRITE_CMD: "Write Command",
        ATT_PREPARE_WRITE_REQ: "Prepare Write Request",
        ATT_PREPARE_WRITE_RSP: "Prepare Write Response",
        ATT_EXECUTE_WRITE_REQ: "Execute Write Request",
        ATT_EXECUTE_WRITE_RSP: "Execute Write Response",
    }

    def __init__(self, filepath: str):
        self.filepath = filepath
        self.packets: List[BtsnoopPacket] = []
        self.connections: List[ConnectionRequest] = []
        self.disconnections: List[DisconnectionEvent] = []
        self.advertisements: List[AdvertisementPacket] = []
        self.gatt_operations: List[GattOperation] = []

    def parse(self):
        """Parse the btsnoop file and extract all events"""
        with open(self.filepath, 'rb') as f:
            # Read and validate header
            header = f.read(16)
            if len(header) < 16:
                raise ValueError("File too small to be a valid btsnoop file")

            magic = header[:8]
            if magic != BTSNOOP_MAGIC:
                raise ValueError(f"Invalid btsnoop magic: {magic}")

            version, datalink = struct.unpack('>II', header[8:16])
            if version != BTSNOOP_VERSION:
                print(f"Warning: Unexpected version {version}, expected {BTSNOOP_VERSION}")
            if datalink != DATALINK_HCI:
                print(f"Warning: Unexpected datalink type {datalink}, expected {DATALINK_HCI}")

            # Read packets
            while True:
                record_header = f.read(24)
                if len(record_header) < 24:
                    break

                _, incl_len, flags, _, ts = struct.unpack(
                    '>IIIIQ', record_header
                )

                packet_data = f.read(incl_len)
                if len(packet_data) < incl_len:
                    break

                # Parse timestamp (microseconds since btsnoop epoch)
                try:
                    timestamp = self.BTSNOOP_EPOCH + timedelta(microseconds=ts)
                except:
                    timestamp = datetime.now()

                # Direction from flags
                direction = 'received' if (flags & 0x01) else 'sent'

                if len(packet_data) > 0:
                    pkt_type = packet_data[0]
                    pkt = BtsnoopPacket(
                        timestamp=timestamp,
                        direction=direction,
                        packet_type=pkt_type,
                        data=packet_data[1:]  # Skip packet type byte
                    )
                    self.packets.append(pkt)
                    self._process_packet(pkt)

    def _process_packet(self, pkt: BtsnoopPacket):
        """Process a packet and extract relevant events"""
        if pkt.packet_type == HCI_EVENT:
            self._process_hci_event(pkt)
        elif pkt.packet_type == HCI_COMMAND:
            self._process_hci_command(pkt)
        elif pkt.packet_type == HCI_ACL_DATA:
            self._process_acl_data(pkt)

    def _process_hci_event(self, pkt: BtsnoopPacket):
        """Process HCI Event packets"""
        if len(pkt.data) < 2:
            return

        event_code = pkt.data[0]
        param_len = pkt.data[1]
        params = pkt.data[2:2+param_len]

        if event_code == EVT_CONNECTION_REQUEST:
            if len(params) >= 10:
                bd_addr = ':'.join(f'{b:02X}' for b in reversed(params[:6]))
                link_type = 'SCO' if params[9] == 0x00 else 'ACL'
                self.connections.append(ConnectionRequest(
                    timestamp=pkt.timestamp,
                    direction=pkt.direction,
                    bd_addr=bd_addr,
                    link_type=link_type,
                    event_type='request'
                ))

        elif event_code == EVT_CONNECTION_COMPLETE:
            if len(params) >= 11:
                status = params[0]
                bd_addr = ':'.join(f'{b:02X}' for b in reversed(params[3:9]))
                link_type = 'SCO' if params[9] == 0x00 else 'ACL'
                self.connections.append(ConnectionRequest(
                    timestamp=pkt.timestamp,
                    direction=pkt.direction,
                    bd_addr=bd_addr,
                    link_type=link_type,
                    event_type=f'complete (status={status})'
                ))

        elif event_code == EVT_DISCONNECTION_COMPLETE:
            if len(params) >= 4:
                status = params[0]
                handle = struct.unpack('<H', params[1:3])[0] & 0x0FFF
                reason = params[3]
                reason_str = self.DISCONNECT_REASONS.get(reason, f"Unknown (0x{reason:02X})")
                self.disconnections.append(DisconnectionEvent(
                    timestamp=pkt.timestamp,
                    handle=handle,
                    reason=reason,
                    reason_str=reason_str
                ))

        elif event_code == EVT_LE_META:
            self._process_le_meta_event(pkt, params)

    def _process_le_meta_event(self, pkt: BtsnoopPacket, params: bytes):
        """Process LE Meta Events (connections, advertisements)"""
        if len(params) < 1:
            return

        subevent = params[0]

        # LE Connection Complete
        if subevent == LE_CONNECTION_COMPLETE:
            if len(params) >= 19:
                status = params[1]
                handle = struct.unpack('<H', params[2:4])[0] & 0x0FFF
                role = "Master" if params[4] == 0 else "Slave"
                addr_type = self.ADDR_TYPES.get(params[5], f"Unknown({params[5]})")
                bd_addr = ':'.join(f'{b:02X}' for b in reversed(params[6:12]))
                self.connections.append(ConnectionRequest(
                    timestamp=pkt.timestamp,
                    direction=pkt.direction,
                    bd_addr=bd_addr,
                    link_type=f'LE ({role}, {addr_type})',
                    event_type=f'le_connection_complete (status={status}, handle=0x{handle:04X})'
                ))

        # LE Enhanced Connection Complete
        elif subevent == LE_ENHANCED_CONNECTION_COMPLETE:
            if len(params) >= 31:
                status = params[1]
                handle = struct.unpack('<H', params[2:4])[0] & 0x0FFF
                role = "Master" if params[4] == 0 else "Slave"
                addr_type = self.ADDR_TYPES.get(params[5], f"Unknown({params[5]})")
                bd_addr = ':'.join(f'{b:02X}' for b in reversed(params[6:12]))
                self.connections.append(ConnectionRequest(
                    timestamp=pkt.timestamp,
                    direction=pkt.direction,
                    bd_addr=bd_addr,
                    link_type=f'LE Enhanced ({role}, {addr_type})',
                    event_type=f'le_enhanced_connection_complete (status={status}, handle=0x{handle:04X})'
                ))

        elif subevent == LE_ADV_REPORT:
            if len(params) < 2:
                return
            num_reports = params[1]
            offset = 2

            for _ in range(num_reports):
                if offset + 9 > len(params):
                    break

                event_type = params[offset]
                addr_type = params[offset + 1]
                bd_addr = ':'.join(f'{b:02X}' for b in reversed(params[offset+2:offset+8]))
                data_len = params[offset + 8]
                offset += 9

                if offset + data_len > len(params):
                    break

                adv_data = params[offset:offset+data_len]
                offset += data_len

                rssi = params[offset] if offset < len(params) else 0
                if rssi > 127:
                    rssi -= 256
                offset += 1

                self.advertisements.append(AdvertisementPacket(
                    timestamp=pkt.timestamp,
                    event_type=event_type,
                    addr_type=self.ADDR_TYPES.get(addr_type, f"Unknown({addr_type})"),
                    bd_addr=bd_addr,
                    rssi=rssi,
                    data=adv_data
                ))

    def _process_hci_command(self, pkt: BtsnoopPacket):
        """Process HCI Command packets"""
        if len(pkt.data) < 3:
            return

        opcode = struct.unpack('<H', pkt.data[:2])[0]
        param_len = pkt.data[2]
        params = pkt.data[3:3+param_len]

        if opcode == CMD_CREATE_CONNECTION:
            if len(params) >= 6:
                bd_addr = ':'.join(f'{b:02X}' for b in reversed(params[:6]))
                self.connections.append(ConnectionRequest(
                    timestamp=pkt.timestamp,
                    direction=pkt.direction,
                    bd_addr=bd_addr,
                    link_type='ACL',
                    event_type='create_connection_cmd'
                ))

        elif opcode == CMD_LE_CREATE_CONNECTION:
            if len(params) >= 8:
                bd_addr = ':'.join(f'{b:02X}' for b in reversed(params[2:8]))
                self.connections.append(ConnectionRequest(
                    timestamp=pkt.timestamp,
                    direction=pkt.direction,
                    bd_addr=bd_addr,
                    link_type='LE',
                    event_type='le_create_connection_cmd'
                ))

        elif opcode == CMD_DISCONNECT:
            if len(params) >= 3:
                handle = struct.unpack('<H', params[:2])[0] & 0x0FFF
                reason = params[2]
                reason_str = self.DISCONNECT_REASONS.get(reason, f"Unknown (0x{reason:02X})")
                self.disconnections.append(DisconnectionEvent(
                    timestamp=pkt.timestamp,
                    handle=handle,
                    reason=reason,
                    reason_str=f"Disconnect Command: {reason_str}"
                ))

    def _process_acl_data(self, pkt: BtsnoopPacket):
        """Process ACL Data packets for GATT operations"""
        if len(pkt.data) < 4:
            return

        # ACL header: handle (2 bytes), length (2 bytes)
        acl_len = struct.unpack('<H', pkt.data[2:4])[0]
        acl_data = pkt.data[4:4+acl_len]

        if len(acl_data) < 4:
            return

        # L2CAP header: length (2 bytes), CID (2 bytes)
        l2cap_len = struct.unpack('<H', acl_data[:2])[0]
        cid = struct.unpack('<H', acl_data[2:4])[0]
        l2cap_data = acl_data[4:4+l2cap_len]

        # Check if this is ATT (GATT)
        if cid == L2CAP_CID_ATT and len(l2cap_data) > 0:
            self._process_att(pkt, l2cap_data)

    def _process_att(self, pkt: BtsnoopPacket, att_data: bytes):
        """Process ATT (Attribute Protocol) PDUs for GATT operations"""
        if len(att_data) < 1:
            return

        opcode = att_data[0]

        # Check if this is a GATT read or write operation
        if opcode in self.ATT_OPCODES:
            operation = self.ATT_OPCODES[opcode]
            handle = None

            # Extract handle for operations that have it
            if opcode in (ATT_READ_REQ, ATT_WRITE_REQ, ATT_WRITE_CMD,
                         ATT_PREPARE_WRITE_REQ) and len(att_data) >= 3:
                handle = struct.unpack('<H', att_data[1:3])[0]

            self.gatt_operations.append(GattOperation(
                timestamp=pkt.timestamp,
                direction=pkt.direction,
                operation=operation,
                handle=handle,
                data=att_data[1:]
            ))

    def generate_report(self) -> str:
        """Generate a text report of all extracted events"""
        lines = []
        lines.append("=" * 70)
        lines.append("BTSNOOP HCI LOG PARSER RESULTS")
        lines.append("=" * 70)

        lines.append(f"\nTotal packets parsed: {len(self.packets)}")

        # Show capture time range
        if self.packets:
            first_ts = self.packets[0].timestamp
            last_ts = self.packets[-1].timestamp
            duration = last_ts - first_ts
            lines.append(f"Capture period: {first_ts} to {last_ts}")
            lines.append(f"Duration: {duration}")

        # Connection Requests
        lines.append(f"\n{'='*70}")
        lines.append(f"CONNECTION REQUESTS ({len(self.connections)})")
        lines.append("=" * 70)
        for conn in self.connections:
            lines.append(f"  [{conn.timestamp}] {conn.direction.upper()}")
            lines.append(f"    BD_ADDR: {conn.bd_addr}")
            lines.append(f"    Type: {conn.link_type} | Event: {conn.event_type}")
            lines.append("")

        # Disconnection Events
        lines.append(f"{'='*70}")
        lines.append(f"DISCONNECTION EVENTS ({len(self.disconnections)})")
        lines.append("=" * 70)
        for disc in self.disconnections:
            lines.append(f"  [{disc.timestamp}]")
            lines.append(f"    Handle: 0x{disc.handle:04X}")
            lines.append(f"    Reason: {disc.reason_str}")
            lines.append("")

        # Advertisement Packets
        lines.append(f"{'='*70}")
        lines.append(f"ADVERTISEMENT PACKETS ({len(self.advertisements)})")
        lines.append("=" * 70)
        for adv in self.advertisements:
            adv_type_str = self.ADV_TYPES.get(adv.event_type, f"Unknown({adv.event_type})")
            lines.append(f"  [{adv.timestamp}]")
            lines.append(f"    BD_ADDR: {adv.bd_addr} ({adv.addr_type})")
            lines.append(f"    Type: {adv_type_str} | RSSI: {adv.rssi} dBm")
            if adv.data:
                lines.append(f"    Data: {adv.data.hex()}")
            lines.append("")

        # GATT Operations
        lines.append(f"{'='*70}")
        lines.append(f"GATT OPERATIONS ({len(self.gatt_operations)})")
        lines.append("=" * 70)
        for gatt in self.gatt_operations:
            lines.append(f"  [{gatt.timestamp}] {gatt.direction.upper()}")
            lines.append(f"    Operation: {gatt.operation}")
            if gatt.handle is not None:
                lines.append(f"    Handle: 0x{gatt.handle:04X}")
            if gatt.data:
                lines.append(f"    Data: {gatt.data.hex()}")
            lines.append("")

        return "\n".join(lines)

    def print_summary(self):
        """Print a summary of all extracted events to console"""
        print(self.generate_report())

    def save_to_file(self, output_path: str):
        """Save the report to a text file"""
        report = self.generate_report()
        with open(output_path, 'w') as f:
            f.write(report)
        print(f"Report saved to: {output_path}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python btsnoop_parser.py <btsnoop_hci.log> [output.txt]")
        print("\nExamples:")
        print("  python btsnoop_parser.py btsnoop_hci.log")
        print("  python btsnoop_parser.py btsnoop_hci.log output.txt")
        sys.exit(1)

    filepath = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None

    try:
        parser = BtsnoopParser(filepath)
        parser.parse()
        parser.print_summary()

        # Save to file if output path provided
        if output_file:
            parser.save_to_file(output_file)
        else:
            # Auto-generate output filename
            base_name = filepath.rsplit('.', 1)[0]
            output_file = f"{base_name}_parsed.txt"
            parser.save_to_file(output_file)

    except FileNotFoundError:
        print(f"Error: File '{filepath}' not found")
        sys.exit(1)
    except ValueError as e:
        print(f"Error: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
