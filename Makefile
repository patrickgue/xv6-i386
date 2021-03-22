OBJS = \
	kernel/bio.o\
	kernel/console.o\
	kernel/exec.o\
	kernel/file.o\
	kernel/fs.o\
	kernel/ide.o\
	kernel/ioapic.o\
	kernel/kalloc.o\
	kernel/kbd.o\
	kernel/lapic.o\
	kernel/log.o\
	kernel/main.o\
	kernel/mp.o\
	kernel/picirq.o\
	kernel/pipe.o\
	kernel/proc.o\
	kernel/sleeplock.o\
	kernel/spinlock.o\
	kernel/string.o\
	kernel/swtch.o\
	kernel/syscall.o\
	kernel/sysfile.o\
	kernel/sysproc.o\
	kernel/trapasm.o\
	kernel/trap.o\
	kernel/uart.o\
	kernel/vectors.o\
	kernel/vm.o\

# Cross-compiling (e.g., on Mac OS X)
TOOLPREFIX = i686-elf-

# Using native tools (e.g., on X86 Linux)
#TOOLPREFIX = 

# Try to infer the correct TOOLPREFIX if not set
ifndef TOOLPREFIX
TOOLPREFIX := $(shell if i386-jos-elf-objdump -i 2>&1 | grep '^elf32-i386$$' >/dev/null 2>&1; \
	then echo 'i386-jos-elf-'; \
	elif objdump -i 2>&1 | grep 'elf32-i386' >/dev/null 2>&1; \
	then echo ''; \
	else echo "***" 1>&2; \
	echo "*** Error: Couldn't find an i386-*-elf version of GCC/binutils." 1>&2; \
	echo "*** Is the directory with i386-jos-elf-gcc in your PATH?" 1>&2; \
	echo "*** If your i386-*-elf toolchain is installed with a command" 1>&2; \
	echo "*** prefix other than 'i386-jos-elf-', set your TOOLPREFIX" 1>&2; \
	echo "*** environment variable to that prefix and run 'make' again." 1>&2; \
	echo "*** To turn off this error, run 'gmake TOOLPREFIX= ...'." 1>&2; \
	echo "***" 1>&2; exit 1; fi)
endif

# If the makefile can't find QEMU, specify its path here
# QEMU = qemu-system-i386

# Try to infer the correct QEMU
ifndef QEMU
QEMU = $(shell if which qemu > /dev/null; \
	then echo qemu; exit; \
	elif which qemu-system-i386 > /dev/null; \
	then echo qemu-system-i386; exit; \
	elif which qemu-system-x86_64 > /dev/null; \
	then echo qemu-system-x86_64; exit; \
	else \
	qemu=/Applications/Q.app/Contents/MacOS/i386-softmmu.app/Contents/MacOS/i386-softmmu; \
	if test -x $$qemu; then echo $$qemu; exit; fi; fi; \
	echo "***" 1>&2; \
	echo "*** Error: Couldn't find a working QEMU executable." 1>&2; \
	echo "*** Is the directory containing the qemu binary in your PATH" 1>&2; \
	echo "*** or have you tried setting the QEMU variable in Makefile?" 1>&2; \
	echo "***" 1>&2; exit 1)
endif

CC = $(TOOLPREFIX)gcc
AS = $(TOOLPREFIX)gas
LD = $(TOOLPREFIX)ld
OBJCOPY = $(TOOLPREFIX)objcopy
OBJDUMP = $(TOOLPREFIX)objdump
CFLAGS = -fno-pic -static -fno-builtin -fno-strict-aliasing -O2 -Wall -MD -ggdb -m32 -Werror -fno-omit-frame-pointer -I./include
CFLAGS += $(shell $(CC) -fno-stack-protector -E -x c /dev/null >/dev/null 2>&1 && echo -fno-stack-protector)
ASFLAGS = -m32 -gdwarf-2 -Wa,-divide -I./include
# FreeBSD ld wants ``elf_i386_fbsd''
LDFLAGS += -m $(shell $(LD) -V | grep elf_i386 2>/dev/null | head -n 1)

# Disable PIE when possible (for Ubuntu 16.10 toolchain)
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]no-pie'),)
CFLAGS += -fno-pie -no-pie
endif
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]nopie'),)
CFLAGS += -fno-pie -nopie
endif

xv6.img: kernel/bootblock kernel/kernel
	dd if=/dev/zero of=xv6.img count=10000
	dd if=kernel/bootblock of=xv6.img conv=notrunc
	dd if=kernel/kernel of=xv6.img seek=1 conv=notrunc

xv6memfs.img: kernel/bootblock kernel/kernelmemfs
	dd if=/dev/zero of=xv6memfs.img count=10000
	dd if=/kernel/bootblock of=xv6memfs.img conv=notrunc
	dd if=/kernel/kernelmemfs of=xv6memfs.img seek=1 conv=notrunc

kernel/bootblock: kernel/bootasm.S kernel/bootmain.c
	$(CC) $(CFLAGS) -fno-pic -O -nostdinc -I. -c kernel/bootmain.c -o kernel/bootmain.o
	$(CC) $(CFLAGS) -fno-pic -nostdinc -I. -c kernel/bootasm.S -o kernel/bootasm.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7C00 -o kernel/bootblock.o kernel/bootasm.o kernel/bootmain.o
	$(OBJDUMP) -S kernel/bootblock.o > kernel/bootblock.asm
	$(OBJCOPY) -S -O binary -j .text kernel/bootblock.o kernel/bootblock
	./sign.pl kernel/bootblock

kernel/entryother: kernel/entryother.S
	$(CC) $(CFLAGS) -fno-pic -nostdinc -I. -c kernel/entryother.S -o kernel/entryother.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7000 -o kernel/bootblockother.o kernel/entryother.o
	$(OBJCOPY) -S -O binary -j .text kernel/bootblockother.o kernel/entryother
	$(OBJDUMP) -S kernel/bootblockother.o > kernel/entryother.asm

kernel/initcode: kernel/initcode.S
	$(CC) $(CFLAGS) -nostdinc -I. -c kernel/initcode.S -o kernel/initcode.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0 -o kernel/initcode.out kernel/initcode.o
	$(OBJCOPY) -S -O binary kernel/initcode.out kernel/initcode
	$(OBJDUMP) -S kernel/initcode.o > kernel/initcode.asm

kernel/kernel: $(OBJS) kernel/entry.o kernel/entryother kernel/initcode kernel/kernel.ld
	$(LD) $(LDFLAGS) -T kernel/kernel.ld -o kernel/kernel kernel/entry.o $(OBJS) -b binary kernel/initcode kernel/entryother
	$(OBJDUMP) -S kernel/kernel > kernel/kernel.asm
	$(OBJDUMP) -t kernel/kernel | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > kernel/kernel.sym

# kernelmemfs is a copy of kernel that maintains the
# disk image in memory instead of writing to a disk.
# This is not so useful for testing persistent storage or
# exploring disk buffering implementations, but it is
# great for testing the kernel on real hardware without
# needing a scratch disk.
MEMFSOBJS = $(filter-out ide.o,$(OBJS)) memide.o
kernelmemfs: $(MEMFSOBJS) kernel/entry.o kernel/entryother kernel/initcode kernel/kernel.ld kernel/fs.img
	$(LD) $(LDFLAGS) -T kernel/kernel.ld -o kernel/kernelmemfs kernel/entry.o  $(MEMFSOBJS) -b binary kernel/initcode kernel/entryother kernel/fs.img
	$(OBJDUMP) -S kernel/kernelmemfs > kernel/kernelmemfs.asm
	$(OBJDUMP) -t kernel/kernelmemfs | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > kernel/kernelmemfs.sym

tags: $(OBJS) kernel/entryother.S _init
	etags *.S *.c

kernel/vectors.S: vectors.pl
	./vectors.pl > kernel/vectors.S

ULIB = lib/ulib.o lib/usys.o lib/printf.o lib/umalloc.o

_%: %.o $(ULIB)
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $@ $^
	$(OBJDUMP) -S $@ > $*.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $*.sym

usr.bin/_forktest: usr.bin/forktest.o $(ULIB)
	# forktest has less library code linked in - needs to be small
	# in order to be able to max out the proc table.
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o usr.bin/_forktest usr.bin/forktest.o lib/ulib.o lib/usys.o
	$(OBJDUMP) -S usr.bin/_forktest > usr.bin/forktest.asm

mkfs: mkfs.c include/kernel/fs.h
	gcc -Werror -Wall -o mkfs mkfs.c -I./include

# Prevent deletion of intermediate files, e.g. cat.o, after first build, so
# that disk image changes after first build are persistent until clean.  More
# details:
# http://www.gnu.org/software/make/manual/html_node/Chained-Rules.html
.PRECIOUS: %.o

UPROGS=\
	usr.bin/_cat\
	usr.bin/_echo\
	usr.bin/_forktest\
	usr.bin/_grep\
	usr.bin/_init\
	usr.bin/_kill\
	usr.bin/_ln\
	usr.bin/_ls\
	usr.bin/_mkdir\
	usr.bin/_rm\
	usr.bin/_sh\
	usr.bin/_stressfs\
	usr.bin/_usertests\
	usr.bin/_wc\
	usr.bin/_zombie\

fs.img: mkfs README $(UPROGS)
	./mkfs fs.img README $(UPROGS)

-include *.d

clean: 
	rm -f *.tex *.dvi *.idx *.aux *.log *.ind *.ilg \
	*.o kernel/*.o *.d kernel/*.d *.asm kernel/*.asm *.sym kernel/vectors.S kernel/bootblock kernel/entryother \
	kernel/initcode kernel/initcode.out kernel/kernel xv6.img fs.img kernelmemfs \
	kernel/xv6memfs.img mkfs .gdbinit \
	$(UPROGS)

# make a printout
FILES = $(shell grep -v '^\#' runoff.list)
PRINT = runoff.list runoff.spec README toc.hdr toc.ftr $(FILES)

xv6.pdf: $(PRINT)
	./runoff
	ls -l xv6.pdf

print: xv6.pdf

# run in emulators

bochs : fs.img xv6.img
	if [ ! -e .bochsrc ]; then ln -s dot-bochsrc .bochsrc; fi
	bochs -q

# try to generate a unique GDB port
GDBPORT = $(shell expr `id -u` % 5000 + 25000)
# QEMU's gdb stub command line changed in 0.11
QEMUGDB = $(shell if $(QEMU) -help | grep -q '^-gdb'; \
	then echo "-gdb tcp::$(GDBPORT)"; \
	else echo "-s -p $(GDBPORT)"; fi)
ifndef CPUS
CPUS := 2
endif
QEMUOPTS = -drive file=fs.img,index=1,media=disk,format=raw -drive file=xv6.img,index=0,media=disk,format=raw -smp $(CPUS) -m 512 $(QEMUEXTRA)

qemu: fs.img xv6.img
	$(QEMU) -serial mon:stdio $(QEMUOPTS)

qemu-memfs: xv6memfs.img
	$(QEMU) -drive file=xv6memfs.img,index=0,media=disk,format=raw -smp $(CPUS) -m 256

qemu-nox: fs.img xv6.img
	$(QEMU) -nographic $(QEMUOPTS)

.gdbinit: .gdbinit.tmpl
	sed "s/localhost:1234/localhost:$(GDBPORT)/" < $^ > $@

qemu-gdb: fs.img xv6.img .gdbinit
	@echo "*** Now run 'gdb'." 1>&2
	$(QEMU) -serial mon:stdio $(QEMUOPTS) -S $(QEMUGDB)

qemu-nox-gdb: fs.img xv6.img .gdbinit
	@echo "*** Now run 'gdb'." 1>&2
	$(QEMU) -nographic $(QEMUOPTS) -S $(QEMUGDB)

# CUT HERE
# prepare dist for students
# after running make dist, probably want to
# rename it to rev0 or rev1 or so on and then
# check in that version.

EXTRA=\
	mkfs.c ulib.c user.h cat.c echo.c forktest.c grep.c kill.c\
	ln.c ls.c mkdir.c rm.c stressfs.c usertests.c wc.c zombie.c\
	printf.c umalloc.c\
	README dot-bochsrc *.pl toc.* runoff runoff1 runoff.list\
	.gdbinit.tmpl gdbutil\

dist:
	rm -rf dist
	mkdir dist
	for i in $(FILES); \
	do \
		grep -v PAGEBREAK $$i >dist/$$i; \
	done
	sed '/CUT HERE/,$$d' Makefile >dist/Makefile
	echo >dist/runoff.spec
	cp $(EXTRA) dist

dist-test:
	rm -rf dist
	make dist
	rm -rf dist-test
	mkdir dist-test
	cp dist/* dist-test
	cd dist-test; $(MAKE) print
	cd dist-test; $(MAKE) bochs || true
	cd dist-test; $(MAKE) qemu

# update this rule (change rev#) when it is time to
# make a new revision.
tar:
	rm -rf /tmp/xv6
	mkdir -p /tmp/xv6
	cp dist/* dist/.gdbinit.tmpl /tmp/xv6
	(cd /tmp; tar cf - xv6) | gzip >xv6-rev10.tar.gz  # the next one will be 10 (9/17)

.PHONY: dist-test dist
