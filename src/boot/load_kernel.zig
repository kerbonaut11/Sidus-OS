const std = @import("std");
const log = std.log.scoped(.load_kernel);
const uefi = std.os.uefi;
const File = uefi.protocol.File;
const elf = std.elf;
const util = @import("util.zig");
const readAll = util.readAll;
const readOne = util.readOne;

const Ehdr = elf.Elf64_Ehdr;
const Phdr = elf.Elf64_Phdr;
const Shdr = elf.Elf64_Shdr;

const Error = error{BadFile}||uefi.Error;

pub fn loadKernel() Error!void {
    const boot_services = uefi.system_table.boot_services.?;
    const fs = (try boot_services.locateProtocol(uefi.protocol.SimpleFileSystem, null)).?;
    const volume = try fs.openVolume();
    const kernel = try volume.open(util.uefiStringLit("kernel"), .read, .{});
    try load(kernel);
}

fn load(file: *File) Error!void {
    const header: Ehdr = try readOne(file, Ehdr);
    log.debug("{}", .{header.e_machine});

    for (0..header.e_phnum) |i| {
        try file.setPosition(header.e_phoff + i*header.e_phentsize);
        const phdr = try readOne(file, Phdr);
        log.debug("vmem 0x{x} @ 0x{x} with aling 0x{}", .{phdr.p_memsz, phdr.p_vaddr, phdr.p_align});
    }
}
