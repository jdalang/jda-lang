# Stage 0: Jda Bootstrapper (x86-64 NASM, Linux)
# Run inside Docker: make all

NASM    = nasm
LD      = ld
NASMFLAGS = -f elf64 -g -F dwarf

all: jda0

jda0: jda0.o
	$(LD) -o jda0 jda0.o

jda0.o: jda0.asm
	$(NASM) $(NASMFLAGS) -o jda0.o jda0.asm

# Test: compile the hello example
test: jda0
	./jda0 ../../examples/hello.jda hello_out
	chmod +x hello_out
	./hello_out

clean:
	rm -f jda0.o jda0 hello_out
