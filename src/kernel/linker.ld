ENTRY(_start)
SECTIONS
{
  . = 0xffff800000000000;

  .text ALIGN(0x200000):
  {
      *(.text)
  }
  .rodata ALIGN(0x200000):
  {
      *(.rodata)
  }
  .data ALIGN(0x200000):
  {
      *(.data)
  }
  .bss ALIGN(0x200000):
  {
      *(.bss)
  }
}
