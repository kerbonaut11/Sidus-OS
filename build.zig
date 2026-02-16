const std = @import("std");
const Build = std.Build;

var optimize: std.builtin.OptimizeMode = undefined;

pub fn build(b: *Build) void {
    optimize = b.standardOptimizeOption(.{});
    const boot_loader = buildBootloader(b);
    const kernel = buildKernel(b);

    const image_type = b.option(enum {img, gpt, iso}, "image-type", "format of the bootable output file") 
        orelse .img;
    const ovmf_path = b.option([]const u8, "omvf", "path to the ovmf bios") 
        orelse "/usr/share/ovmf/x64/OVMF.4m.fd";

    var make_image = b.addSystemCommand(&.{"sh"});
    make_image.addFileArg(b.path("mkimage.sh"));
    make_image.addArg(@tagName(image_type));
    const fat_img = make_image.addOutputFileArg("fat.img");
    make_image.addArtifactArg(boot_loader);
    make_image.addArtifactArg(kernel);
    const image = switch (image_type) {
        .gpt => make_image.addOutputFileArg("hdimage.bin"),
        .img => fat_img,
        .iso => make_image.addOutputFileArg("cdimage.iso"),
    };

    const gdb = b.option(bool, "gdb", "enbale QEMU gdb debugging") orelse false;
    const kvm = b.option(bool, "kvm", "make QEMU use KVM") orelse false;

    var qemu_cmd = b.addSystemCommand(&.{"qemu-system-x86_64"});
    qemu_cmd.addArgs(&.{"-smbios", "type=0,uefi=on"});
    qemu_cmd.addArgs(&.{"-bios", ovmf_path});
    qemu_cmd.addArgs(&.{"-m", "256M"});
    qemu_cmd.addArgs(&.{"-usb"});
    qemu_cmd.addArgs(&.{"-device", "qemu-xhci"});
    qemu_cmd.addArgs(&.{"-device", "nvme,serial=ffaa"});

    if (kvm) qemu_cmd.addArgs(&.{"-enable-kvm", "-cpu", "host"});
    if (gdb) qemu_cmd.addArgs(&.{"-s", "-S"});

    switch (image_type) {
        .gpt, .img => qemu_cmd.addArg("-hda"),
        .iso => qemu_cmd.addArg("-cdrom"),
    }
    qemu_cmd.addFileArg(image);

    const run_step = b.step("run", "run HD image with QEMU");
    run_step.dependOn(&qemu_cmd.step);

    const install_file_name = switch (image_type) {
        .gpt => "hdimage.bin",
        .img => "fat.img",
        .iso => "cdimage.iso",
    };
    const install_file = b.addInstallFile(image, install_file_name);
    b.getInstallStep().dependOn(&install_file.step);

    const kernel_install = b.addInstallArtifact(kernel, .{});
    b.step("kernel-elf", "output kernel as elf").dependOn(&kernel_install.step);
    if (gdb) qemu_cmd.step.dependOn(&kernel_install.step);

    const boot_loader_install = b.addInstallArtifact(boot_loader, .{});
    b.step("boot-loader-exe", "output bootloader as exe").dependOn(&boot_loader_install.step);
}

pub fn buildBootloader(b: *Build) *Build.Step.Compile {
    return b.addExecutable(.{
        .name = "boot-loader",
        .root_module = b.addModule("boot", .{
            .root_source_file = b.path("src/boot/main.zig"),
            .target = b.resolveTargetQuery(.{
                .abi = .msvc,
                .cpu_arch = .x86_64,
                .os_tag = .uefi,
            }),
            .optimize = optimize,
        })
    });
}

pub fn buildKernel(b: *Build) *Build.Step.Compile {
    const exe =  b.addExecutable(.{
        .name = "kernel",
        .root_module = b.addModule("kernel", .{
            .root_source_file = b.path("src/kernel/main.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .x86_64,
                .os_tag = .freestanding,
            }),
            .code_model = .kernel,
            .pic = true,
            .optimize = optimize,
        }), 
        .use_llvm = true,
    });

    exe.root_module.addImport("boot", b.addModule("{}", .{
        .root_source_file = b.path("src/boot/root.zig")
    }));
    exe.setLinkerScript(b.path("src/kernel/linker.ld"));

    return exe;
}
