const std = @import("std");
const log = std.log.scoped(.load_kernel);
const uefi = std.os.uefi;
const File = uefi.protocol.File;
const elf = std.elf;
const util = @import("util.zig");
const readAll = util.readAll;
const readOne = util.readOne;
const mem = @import("mem.zig");

const Ehdr = elf.Elf64_Ehdr;
const Phdr = elf.Elf64_Phdr;
const Shdr = elf.Elf64_Shdr;

//returns the entry point
pub fn loadKernel() !usize {
    const boot_services = uefi.system_table.boot_services.?;
    const fs = (try boot_services.locateProtocol(uefi.protocol.SimpleFileSystem, null)).?;
    const volume = try fs.openVolume();
    const kernel = try volume.open(util.uefiStringLit("kernel"), .read, .{});
    log.info("located kernel elf", .{});
    return try load(kernel);
}

fn load(file: *File) !usize {
    const header: Ehdr = try readOne(file, Ehdr);

    const Range = struct {start: usize, end: usize};
    var buffer: [128]Range = undefined;
    var already_mapped_ranges = std.ArrayList(Range).initBuffer(&buffer);

    for (0..header.e_phnum) |i| {
        try file.setPosition(header.e_phoff + i*header.e_phentsize);
        const phdr = try readOne(file, Phdr);

        if (phdr.p_type != elf.PT_LOAD) continue;
        log.debug("0x{x} byte section @ 0x{x}", .{phdr.p_memsz, phdr.p_vaddr});

        const align_back = phdr.p_vaddr % mem.page_size;
        const num_pages = std.mem.alignForward(usize, phdr.p_memsz, mem.page_size)/mem.page_size;
        var map_range = Range{
            .start = phdr.p_vaddr - align_back,
            .end = phdr.p_vaddr - align_back + num_pages*mem.page_size,
        };

        for (already_mapped_ranges.items) |range| {
            const start_in_range = map_range.start >= range.start and map_range.start < range.end;
            const end_in_range = map_range.end >= range.start and map_range.end < range.end;
            if (start_in_range and end_in_range) {
                map_range.start = 0;
                map_range.end = 0;
                break;
            } else if (start_in_range) {
                map_range.start = range.end;
            } else if (end_in_range) {
                map_range.end = range.start;
            }
        }

        const execute = phdr.p_flags & elf.PF_X != 0;
        try mem.createMap(map_range.start, @divExact(map_range.end-map_range.start, mem.page_size), true, execute);

        already_mapped_ranges.appendAssumeCapacity(map_range);

        try file.setPosition(phdr.p_offset);
        try readAll(file, @as([*]u8, @ptrFromInt(phdr.p_vaddr))[0..phdr.p_filesz]);

        log.debug("copied 0x{} bytes from kernel elf", .{phdr.p_memsz});
    }

    log.debug("kernel entry: 0x{x}", .{header.e_entry});
    return header.e_entry;
}
