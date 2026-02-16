const std = @import("std");
const io = @import("../../io.zig");
const pci = io.pci;
const mmio = io.mmapped;
const mem = @import("../../mem.zig");
const log = std.log.scoped(.nvme);

const Error = error{QueueFull, QueueEmpty} || std.mem.Allocator.Error;

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
        opcode: u8,
        _pad0: u8 = 0,
        command_id: u16,

        nsid: u32 = 0,
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

    pub fn write(queue: *Queue, regs: *volatile Regs, data: SubmissionEntry) !void {
        if ((queue.tail+1)%num_entries == queue.head) return Error.QueueFull;

        queue.submission_entries[queue.tail] = data;
        queue.tail += 1;
        regs.ringDoorbell(queue.id, queue.tail, false);
    }

    pub fn read(queue: *Queue, regs: *volatile Regs) !CompletionEntry {
        if (queue.tail == queue.head) return Error.QueueEmpty;

        const data = queue.completion_entries[queue.head];
        queue.head += 1;
        regs.ringDoorbell(queue.id, queue.head, true);

        return data;
    }
};

const Driver = struct {
    regs: *volatile Regs,
};

comptime {
    std.debug.assert(@offsetOf(Regs, "admin_queue_lengths") == 0x24);
    std.debug.assert(@sizeOf(Queue.SubmissionEntry) == 64);
    std.debug.assert(@sizeOf(Queue.CompletionEntry) == 16);
}


pub fn init(device: *const pci.Device) !void {
    const base_addr = device.baseAddresRegister(0);
    const regs_raw = try mmio.createSlice(u8, base_addr, Regs.doorbells_offset+Regs.max_doorbell_bytes);
    regs_raw[0] = 0xaf;
    const regs: *volatile Regs = @ptrCast(@alignCast(regs_raw.ptr));

    regs.config = @bitCast(@as(u32, 0));
    while (regs.status.ready) {}

    var admin_queue = try Queue.initAdmin(regs);

    regs.config = .{
        .io_command_set_select = 0b110,
        .io_submission_queue_entry_size_log2 = @intCast(std.math.log2_int(usize, @sizeOf(Queue.SubmissionEntry))), 
        .io_completion_queue_entry_size_log2 = @intCast(std.math.log2_int(usize, @sizeOf(Queue.CompletionEntry))), 
        .enable = true,
    };

    while (!regs.status.ready) {}

    admin_queue.write(regs, .{.command_id = 1, .nsid = 0, .opcode = 0x14, .dword10 = 1}) catch unreachable;

    while (!admin_queue.completion_entries[admin_queue.head].phase_tag) {}
    log.debug("{x}", .{(try admin_queue.read(regs)).status});

}
