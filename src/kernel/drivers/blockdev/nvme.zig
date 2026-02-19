const std = @import("std");
const io = @import("../../io.zig");
const pci = io.pci;
const mmio = io.mmapped;
const mem = @import("../../mem.zig");
const log = std.log.scoped(.nvme);
const BlockDev = @import("BlockDev.zig");

const Error = error{CommandFailed, QueueFull, QueueEmpty, NotReady} || std.mem.Allocator.Error;

const Regs = packed struct {
    const doorbells_offset = 0x1000;
    const max_doorbell_bytes = 4096;

    const Cap = packed struct(u64) {
        maximum_queue_entries: u16,
        contiguous_queues_required: bool,
        arbitration_mechanism_supported: u2,
        _pad0: u5,
        timeout: u8,
        doorbell_stride_log2: u4,
        nvm_subsystem_reset: bool,
        command_set_support: u8,
        _pad1: u19,
    };

    const Config = packed struct(u32) {
        enable: bool,
        _pad0: u3 = 0,
        io_command_set_select: u3 = 0,
        memory_page_size: u4 = 0,
        abritation_mechanism_selected: u3 = 0,
        shutdown_notification: u2 = 0,
        io_submission_queue_entry_size_log2: u4,
        io_completion_queue_entry_size_log2: u4,
        _pad1: u8 = 0,
    };

    const Status = packed struct(u32) {
        ready: bool,
        _pad0: u31,
    };

    cap: Cap,
    version: u32,
    interrupt_mask_set: u32,
    interrupt_mask_clear: u32,
    config: Config,
    _pad: u32,
    status: Status,
    nvm_subsystem_reset: u32,
    admin_queue_lengths: u32,
    admin_submission_queue: usize,
    admin_completion_queue: usize,

    pub fn ringDoorbell(regs: *volatile Regs, queue_id: u16, val: u32, completion: bool) void {
        const stride = @as(usize, 4) << regs.cap.doorbell_stride_log2;
        const offset = (queue_id*2 + @intFromBool(completion)) * stride;
        const ptr: *volatile u32 = @ptrFromInt(@intFromPtr(regs)+doorbells_offset+offset);
        ptr.* = val;
    }
};

const Queue = packed struct {
    const SubmissionEntry = packed struct {
        opcode: packed union {
            admin: enum(u8) {
                delete_io_submission_queue = 0x00,
                create_io_submission_queue = 0x01,
                delete_io_completion_queue = 0x04,
                create_io_completion_queue = 0x05,
                identify = 0x06,
            },

            io: enum(u8) {
                write = 0x01,
                read = 0x02,
            },
        },
        _pad0: u8 = 0,
        command_id: u16 = 0,

        namespace_id: u32 = 0,
        _pad1: u64 = 0,
        metadata_ptr: usize = 0,
        data_ptr_1: usize = 0,
        data_ptr_2: usize = 0,
        dword10: u32 = 0,
        dword11: u32 = 0,
        dword12: u32 = 0,
        dword14: u32 = 0,
        dword15: u32 = 0,
    };

    const CompletionEntry = packed struct {
        dword0: u32 = 0,
        dword1: u32 = 0,
        submission_queue_head_pointer: u16,
        submission_queue_id: u16,
        command_id: u16,
        phase_tag: bool,
        status: u15,
    };

    const num_entries = mem.page_size/@sizeOf(SubmissionEntry);

    id: u16,
    submission_addr: usize,
    submission_entries: *volatile [num_entries]SubmissionEntry,
    completion_addr: usize,
    completion_entries: *volatile [num_entries]CompletionEntry,
    tail: u32,
    head: u32,

    pub fn init(id: u16) !Queue {
        const submission_addr = try mem.page_allocator.alloc();
        const submission_entries = try mmio.create([num_entries]SubmissionEntry, submission_addr);
        const completion_addr = try mem.page_allocator.alloc();
        const completion_entries = try mmio.create([num_entries]CompletionEntry, completion_addr);
        @memset(std.mem.sliceAsBytes(completion_entries), 0);

        return .{
            .id = id,
            .submission_addr = submission_addr,
            .submission_entries = submission_entries,
            .completion_addr = completion_addr,
            .completion_entries = completion_entries,
            .tail = 0,
            .head = 0,
        };
    }

    pub fn initAdmin(regs: *volatile Regs) !Queue {
        const queue = try Queue.init(0);
        regs.admin_submission_queue = queue.submission_addr;
        regs.admin_completion_queue = queue.completion_addr;
        regs.admin_queue_lengths = (num_entries-1 << 16) | num_entries-1;
        return queue;
    }

    pub fn initIO(admin_queue: *Queue, regs: *volatile Regs, id: u16) !Queue {
        const queue = try Queue.init(id);

        try admin_queue.submitBlocking(regs, .{
            .opcode = .{.admin = .create_io_completion_queue},
            .data_ptr_1 = queue.completion_addr,
            .data_ptr_2 = queue.completion_addr,
            .dword10 = @as(u32, num_entries-1 << 16) | id,
            .dword11 = 1,
        });

        try admin_queue.submitBlocking(regs, .{
            .opcode = .{.admin = .create_io_submission_queue},
            .data_ptr_1 = queue.submission_addr,
            .data_ptr_2 = queue.submission_addr,
            .dword10 = @as(u32, num_entries-1 << 16) | id,
            .dword11 = @as(u32, id) << 16 | 1,
        });

        log.debug("created IO Queue", .{});

        return queue;
    }

    pub fn write(queue: *Queue, regs: *volatile Regs, data: SubmissionEntry) !void {
        if ((queue.tail+1)%num_entries == queue.head) return Error.QueueFull;

        queue.submission_entries[queue.tail] = data;
        queue.tail += 1;
        regs.ringDoorbell(queue.id, queue.tail, false);
    }

    pub fn read(queue: *Queue, regs: *volatile Regs) !CompletionEntry {
        if (queue.tail == queue.head) return Error.QueueEmpty;

        if (!queue.completion_entries[queue.head].phase_tag) return Error.NotReady;
        queue.completion_entries[queue.head].phase_tag = false;

        const data = queue.completion_entries[queue.head];
        queue.head += 1;
        regs.ringDoorbell(queue.id, queue.head, true);

        if (data.status != 0) {
            log.debug("type: {x} code: {x} {b}", .{data.status >> 8 & 0b111, data.status & 0xff, data.status});
            return error.CommandFailed;
        }

        return data;
    }

    pub fn submitBlocking(queue: *Queue, regs: *volatile Regs, command: SubmissionEntry) !void {
        try queue.write(regs, command);
        while (true) {
            _ = queue.read(regs) catch |err| if (err == error.NotReady) continue else return err;
            break;
        }
    }
};

const NamespaceInfoRaw = extern struct {
    size_blocks: u64,
    capacity_blocks: u64,
    used_blocks: u64,
    features: u8,
    block_format_count: u8,
    formatted_size: packed struct(u8) {idx_lo: u4, metadata_at_end_of_block: bool, idx_hi: u2, _pad: u1},
    _pad: [100]u8,

    block_formats: [64]packed struct(u32) {metadata_size: u16, block_size_log2: u8, _pad: u8},
};

const NamespaceInfo = struct {
    id: u32,

    size_blocks: u64,
    capacity_blocks: u64,
    used_blocks: u64,

    block_size: u64,
    metadata_size: u16,
    metadata_at_end_of_block: bool,
};

const Driver = struct {
    pci: *const pci.Device,
    regs: *volatile Regs,
    admin_queue: Queue,
    io_queue: Queue,

    fn init(device: *const pci.Device) !Driver {
        const base_addr = device.baseAddresRegister(0);
        const regs_raw = try mmio.createSlice(u8, base_addr, Regs.doorbells_offset+Regs.max_doorbell_bytes);
        const regs: *volatile Regs = @ptrCast(@alignCast(regs_raw));

        regs.config = @bitCast(@as(u32, 0));
        while (regs.status.ready) {}

        var admin_queue = try Queue.initAdmin(regs);

        regs.interrupt_mask_clear = std.math.maxInt(u32);
        regs.config = .{
            .io_command_set_select = 0b110,
            .io_submission_queue_entry_size_log2 = @intCast(std.math.log2_int(usize, @sizeOf(Queue.SubmissionEntry))), 
            .io_completion_queue_entry_size_log2 = @intCast(std.math.log2_int(usize, @sizeOf(Queue.CompletionEntry))), 
            .enable = true,
        };

        while (!regs.status.ready) {}

        const io_queue = Queue.initIO(&admin_queue, regs, 1) catch unreachable;

        return .{
            .pci = device,
            .regs = regs,
            .admin_queue = admin_queue,
            .io_queue = io_queue,
        };
    }

    fn enumerateNamespaces(driver: *Driver) ![]Namespace {
        const namespace_list_addr = try mem.page_allocator.alloc();
        const namespace_list = mem.physToVirt([*]u32, namespace_list_addr);
        defer mem.page_allocator.free(namespace_list_addr);

        try driver.admin_queue.submitBlocking(driver.regs, .{
            .opcode = .{.admin = .identify},
            .data_ptr_1 = namespace_list_addr,
            .dword10 = 0x02,
        });
        const namespace_count = std.mem.indexOfScalar(u32, namespace_list[0..1024], 0) orelse 1024;

        const namespace_info_addr = try mem.page_allocator.alloc();
        const namespace_info = mem.physToVirt(*NamespaceInfoRaw, namespace_info_addr);
        defer mem.page_allocator.free(namespace_info_addr);

        const interfaces_addr = try mem.page_allocator.alloc();
        const interfaces = mem.physToVirt(*[mem.page_size/@sizeOf(Namespace)]Namespace, interfaces_addr);

        for (namespace_list[0..namespace_count], interfaces[0..namespace_count]) |namespace_id, *interface| {
            try driver.admin_queue.write(driver.regs, .{
                .opcode = .{.admin = .identify},
                .namespace_id = namespace_id,
                .data_ptr_1 = namespace_info_addr,
                .dword10 = 0x00,
            });

            const format_idx = @as(usize, namespace_info.formatted_size.idx_hi) << 4 | namespace_info.formatted_size.idx_lo;
            const format = namespace_info.block_formats[format_idx];
            const block_size = @as(u64, 1) << @truncate(format.block_size_log2);

            interface.* = .{
                .driver = driver,
                .info = .{
                    .id = namespace_id,
                    .size_blocks = namespace_info.size_blocks,
                    .capacity_blocks = namespace_info.capacity_blocks,
                    .used_blocks = namespace_info.used_blocks,
                    .block_size = block_size,
                    .metadata_at_end_of_block = namespace_info.formatted_size.metadata_at_end_of_block,
                    .metadata_size = format.metadata_size,
                },
                .block_dev = .{
                    .block_size = block_size,
                    .vtable = .{
                        .read = Namespace.read,
                        .write = Namespace.write,
                    },
                },
            };
        }

        return interfaces[0..namespace_count];
    }

    fn read(driver: *Driver, namespace: *const NamespaceInfo, start_block: u64, buffer: BlockDev.Buffer) !void {
        for (buffer, 0..) |*page, i| {
            const block = start_block + i*(mem.page_size/namespace.block_size);
            try driver.io_queue.submitBlocking(driver.regs, .{
                .opcode = .{.io = .read},
                .namespace_id = namespace.id,
                .data_ptr_1 = mem.virtToPhys(page, .{}).?,
                .dword10 = @truncate(block),
                .dword11 = @truncate(block >> 32),
                .dword12 = @intCast(mem.page_size/namespace.block_size),
            });
        }
    }

    fn write(driver: *Driver, namespace: *const NamespaceInfo, start_block: u64, buffer: BlockDev.BufferConst) !void {
        for (buffer, 0..) |*page, i| {
            const block = start_block + i*(mem.page_size/namespace.block_size);
            try driver.io_queue.submitBlocking(driver.regs, .{
                .opcode = .{.io = .write},
                .namespace_id = namespace.id,
                .data_ptr_1 = mem.virtToPhys(page, .{}).?,
                .dword10 = @truncate(block),
                .dword11 = @truncate(block >> 32),
                .dword12 = @intCast(mem.page_size/namespace.block_size),
            });
        }
    }
};

const Namespace= struct {
    driver: *Driver,
    info: NamespaceInfo,
    block_dev: BlockDev,

    fn read(block_dev: *BlockDev, start_block: u64, buffer: BlockDev.Buffer) BlockDev.Error!void {
        const self: *Namespace = @fieldParentPtr("block_dev", block_dev);
        return self.driver.read(&self.info, start_block, buffer) catch unreachable;
    }

    fn write(block_dev: *BlockDev, start_block: u64, buffer: BlockDev.BufferConst) BlockDev.Error!void {
        const self: *Namespace = @fieldParentPtr("block_dev", block_dev);
        return self.driver.write(&self.info, start_block, buffer) catch unreachable;
    }
};

comptime {
    std.debug.assert(@offsetOf(Regs, "admin_queue_lengths") == 0x24);
    std.debug.assert(@sizeOf(Queue.SubmissionEntry) == 64);
    std.debug.assert(@sizeOf(Queue.CompletionEntry) == 16);
    std.debug.assert(@offsetOf(NamespaceInfoRaw, "block_formats") == 128);
}


pub fn init(device: *const pci.Device) !void {
    var driver = try Driver.init(device);
    const namespaces = try driver.enumerateNamespaces();
    var buf: [4096]u8 align(4096) = @splat(0x69);
    namespaces[0].block_dev.write(0, @ptrCast(&buf)) catch {};
    buf = @splat(0);
    namespaces[0].block_dev.read(0, @ptrCast(&buf)) catch {};
    log.debug("{x}", .{buf});
}
