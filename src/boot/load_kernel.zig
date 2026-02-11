const std = @import("std");
const log = std.log.scoped(.load_kernel);
const uefi = std.os.uefi;
const File = uefi.protocol.File;
const elf = std.elf;
const util = @import("util.zig");
const readAll = util.readAll;
const readOne = util.readOne;
const vmem = @import("mem.zig");

const Ehdr = elf.Elf64_Ehdr;
const Phdr = elf.Elf64_Phdr;
const Shdr = elf.Elf64_Shdr;

const Error = error{BadFile}||uefi.Error;

//returns the entry point
pub fn loadKernel() Error!usize {
    const boot_services = uefi.system_table.boot_services.?;
    const fs = (try boot_services.locateProtocol(uefi.protocol.SimpleFileSystem, null)).?;
    const volume = try fs.openVolume();
    const kernel = try volume.open(util.uefiStringLit("kernel"), .read, .{});
    return try load(kernel);
}

fn load(file: *File) Error!usize {
    const header: Ehdr = try readOne(file, Ehdr);

    const Range = struct {start: usize, end: usize};
    var buffer: [128]Range = undefined;
    var already_mapped_ranges = std.ArrayList(Range).initBuffer(&buffer);

    for (0..header.e_phnum) |i| {
        try file.setPosition(header.e_phoff + i*header.e_phentsize);
        const phdr = try readOne(file, Phdr);

        if (phdr.p_type != elf.PT_LOAD) continue;
        log.debug("0x{x} byte section @ 0x{x}", .{phdr.p_memsz, phdr.p_vaddr});

        var already_mapped = false;
        for (already_mapped_ranges.items) |range| {
            if (phdr.p_vaddr >= range.start and phdr.p_vaddr < range.end) {
                already_mapped = true;
                std.debug.assert(phdr.p_vaddr+phdr.p_memsz < range.end);
                break;
            }
        }

        if (!already_mapped) {
            const pages = std.mem.alignForward(usize, phdr.p_memsz, vmem.page_size)/vmem.page_size;
            const execute = phdr.p_flags & elf.PF_X != 0;
            try vmem.createMap(phdr.p_vaddr, pages, true, execute);

            already_mapped_ranges.appendAssumeCapacity(.{.start = phdr.p_vaddr, .end = phdr.p_vaddr+pages*vmem.page_size});
        }

        try file.setPosition(phdr.p_offset);
        try readAll(file, @as([*]u8, @ptrFromInt(phdr.p_vaddr))[0..phdr.p_filesz]);

        log.debug("copied 0x{} bytes from kernel elf", .{phdr.p_memsz});
    }

    log.debug("kernel entry: 0x{x}", .{header.e_entry});
    return header.e_entry;
}
