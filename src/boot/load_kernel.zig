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
    const boot_services = uefi.system_table.boot_services.?;

    const header: Ehdr = try readOne(file, Ehdr);
    log.debug("{}", .{header.e_machine});

    for (0..header.e_phnum) |i| {
        try file.setPosition(header.e_phoff + i*header.e_phentsize);
        const phdr = try readOne(file, Phdr);

        if (phdr.p_type == elf.PT_GNU_EH_FRAME or phdr.p_type == elf.PT_GNU_STACK) continue;
        log.debug("vmem 0x{x} @ 0x{x} with aling 0x{}", .{phdr.p_memsz, phdr.p_vaddr, phdr.p_align});

        const pages = std.mem.alignForward(usize, phdr.p_memsz, vmem.page_size)/vmem.page_size;
        const segment_data = try boot_services.allocatePages(.any, .loader_code, pages);
        try vmem.map(@intFromPtr(segment_data.ptr), phdr.p_vaddr, pages);

        try file.setPosition(phdr.p_offset);
        try readAll(file, @as([*]u8, @ptrCast(segment_data.ptr))[0..phdr.p_filesz]);

        log.debug("copied 0x{} bytes from kernel elf", .{phdr.p_memsz});
    }

    log.debug("kernel entry: 0x{x}", .{header.e_entry});
    return header.e_entry;
}
