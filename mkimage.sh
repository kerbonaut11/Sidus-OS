#!/bin/sh

mode=$1
img=$2
boot_loader_elf=$3
kernel_elf=$4
out=$5

dd if=/dev/zero of=$img bs=1k count=28000
mkfs.vfat $img
loop_dev=$(udisksctl loop-setup -f $img)
loop_dev="${loop_dev##* }"
loop_dev=${loop_dev::-1}
>&2 echo "loop dev:"
>&2 echo $loop_dev


img_mnt=$(udisksctl mount -b $loop_dev)
img_mnt="${img_mnt##* }"
>&2 echo "img mnt:"
>&2 echo $img_mnt

mkdir $img_mnt/EFI
mkdir $img_mnt/EFI/BOOT
cp $boot_loader_elf $img_mnt/EFI/BOOT/BOOTX64.EFI
cp $kernel_elf $img_mnt/kernel

case $mode in
  gpt)
    mkgpt -o $out --image-size 102400 --part $img --type system
    ;;
  iso)
    mkdir iso
    cp $img iso
    xorriso -as mkisofs -R -f -e fat.img -no-emul-boot -o $out iso
    rm -r iso
    ;;
  img)
    ;;
esac

udisksctl unmount -b $loop_dev
udisksctl loop-delete -b $loop_dev
