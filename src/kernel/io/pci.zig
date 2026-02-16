const std = @import("std");
const io = @import("../io.zig");
const mem = @import("../mem.zig");
const log = std.log.scoped(.pci);

const config_address = 0xcf8;
const config_data = 0xcfc;
const DeviceIdx = u5;
const BusIdx = u8;
const FunctionIdx = u3;

pub const Address = packed struct(u32) {
    reg_offset: u8,
    function: FunctionIdx,
    device: DeviceIdx,
    bus: BusIdx,
    _pad: u7 = 0,
    enable: bool = true,

    fn read(addr: Address) u32 {
        if (!std.mem.isAligned(addr.reg_offset, 4)) {
            @panic("pci addres must be aligned");
        }
        io.outl(config_address, @bitCast(addr));
        return io.inl(config_data);
    }
};

pub const Device = struct {
    const Class = enum(u16) {
        vga_compatible_display_controller = 0x0300,

        scsi_bus_controller = 0x0100,
        ide_controller,
        floppy_disk_controller,
        ipi_bus_controller,
        raid_controller,
        ata_controller,
        serial_ata_controller,
        serial_attached_scsi_controller,
        nvm_controller,

        host_bridge = 0x0600,
        isa_bridge,
        eisa_bridge,
        mca_bridge,
        pci_pci_bridge,
        pcmcia_bridge,
        nu_bus_bridge,
        card_bus_bridge,
        raceway_bridge,
        pci_pci_bridge_semi_transperent,
        infiniband_pci_bridge,

        fire_wire_controller = 0x0c00,
        access_bus_controller,
        ssa,
        usb_controller,

        _
    };

    const ProgrammingInterface = extern union {
        byte: u8,
        nvm_controller: enum(u8) {
            basic = 1,
            express = 2,
            _,
        },
        usb_controller: enum(u8) {
            uhci = 0x00,
            ohci = 0x10,
            ehci = 0x20,
            xhci = 0x30,
            _,
        }
    };

    bus: BusIdx,
    device_idx: DeviceIdx,

    vendor_id: u16,
    device_id: u16,

    revision_id: u8,
    programming_interface: ProgrammingInterface,
    class: Class,

    chache_line_size: u8,
    latency_timer: u8,
    header_type: u8,
    self_test: u8,

    pub fn init(bus: u8, device: u5) ?Device {
        var addr = Address{
            .reg_offset = 0,
            .function = 0,
            .bus = bus,
            .device = device,
        };
        const vendor_id, const device_id = @as([2]u16, @bitCast(addr.read()));
        if (vendor_id == 0xffff) return null;

        addr.reg_offset = 0x8;
        const revision_id, const programming_interface, const sub_class, const class = @as([4]u8, @bitCast(addr.read()));

        addr.reg_offset = 0xc;
        const chache_line_size, const latency_timer, const header_type, const self_test = @as([4]u8, @bitCast(addr.read()));

        return Device{
            .device_idx = device,
            .bus = bus,

            .vendor_id = vendor_id,
            .device_id = device_id,

            .revision_id = revision_id,
            .programming_interface = .{.byte = programming_interface},
            .class = @enumFromInt(@as(u16, class) << 8 | sub_class),

            .chache_line_size = chache_line_size,
            .latency_timer = latency_timer,
            .header_type = header_type,
            .self_test = self_test,
        };
    }

    pub fn read(device: *const Device, offset: u8) u32 {
        const addr = Address{
            .reg_offset = offset,
            .function = 0,
            .bus = device.bus,
            .device = device.device_idx,
        };
        return addr.read();
    }

    pub fn baseAddresRegister(device: *const Device, idx: u8) usize {
        const lo: u64 = device.read(0x10+idx*@sizeOf(usize));
        const mask =  ~@as(u64, if (lo & 1 == 1) 0b11 else 0b1111);
        const hi: u64 = device.read(0x14+idx*@sizeOf(usize));
        return (hi << 32 | lo) & mask;
    }
};

pub var devices: []Device = undefined;

pub fn enumerateDevices() !void {
    var devices_buf = std.ArrayList(Device).empty;
    for (0..std.math.maxInt(u8)) |bus| {
        for (0..std.math.maxInt(u5)) |device_idx| {
            const device = Device.init(@intCast(bus), @intCast(device_idx)) orelse continue;
            try devices_buf.append(mem.init_allocator, device);
        }
    }

    devices_buf.shrinkAndFree(mem.init_allocator, devices_buf.items.len);
    devices = devices_buf.items;
}
