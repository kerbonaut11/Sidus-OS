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

    for (0..header.e_phnum) |i| {
        try file.setPosition(header.e_phoff + i*header.e_phentsize);
        const phdr = try readOne(file, Phdr);

        if (phdr.p_type != elf.PT_LOAD) continue;
        log.debug("0x{x} byte section @ 0x{x}", .{phdr.p_memsz, phdr.p_vaddr});

        const map_start = std.mem.alignBackward(usize, phdr.p_vaddr, mem.page_size);
        const map_end = std.mem.alignForward(usize, phdr.p_vaddr+phdr.p_memsz, mem.page_size);

        const execute = phdr.p_flags & elf.PF_X != 0;
        try mem.createMap(map_start, @divExact(map_end-map_start, mem.page_size), true, execute);

        try file.setPosition(phdr.p_offset);
        log.debug("{x} {x} {x}", .{phdr.p_vaddr, phdr.p_vaddr+phdr.p_filesz, phdr.p_memsz});
        try readAll(file, @as([*]u8, @ptrFromInt(phdr.p_vaddr))[0..phdr.p_filesz]);
        @memset(@as([*]u8, @ptrFromInt(phdr.p_vaddr))[phdr.p_filesz..phdr.p_memsz], 0);

        log.debug("copied 0x{x} bytes from kernel elf to 0x{x}", .{phdr.p_filesz, phdr.p_vaddr});
    }

    log.debug("kernel entry: 0x{x}", .{header.e_entry});
    return header.e_entry;
}
