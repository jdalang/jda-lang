# Stage 0: Jda Bootstrapper (x86-64 NASM, Linux)
# Run inside Docker: make all

NASM      = nasm
LD        = ld
NASMFLAGS = -f elf64 -g -F dwarf

JDA0      = ./jda0
JDA1_SRC  = ../stage1/jda1.jda
JDA1_BIN  = jda1
HELLO_SRC = ../../examples/hello.jda

all: jda0

# -------------------------------------------------------
# Stage 0: assembler → jda0 binary
# -------------------------------------------------------
jda0: jda0.o
	$(LD) -o jda0 jda0.o

jda0.o: jda0.asm
	$(NASM) $(NASMFLAGS) -o jda0.o jda0.asm

# -------------------------------------------------------
# Stage 1: compile jda1.jda using jda0
# -------------------------------------------------------
stage1: jda0
	$(JDA0) $(JDA1_SRC) $(JDA1_BIN)
	chmod +x $(JDA1_BIN)
	@echo "[stage1] jda1 binary ready."

# Test Stage 1: use jda1 to compile hello.jda
test-stage1: stage1
	./$(JDA1_BIN) $(HELLO_SRC) hello_s1
	chmod +x hello_s1
	./hello_s1
	@echo "[test-stage1] PASS"

# -------------------------------------------------------
# Self-hosting: jda1 compiles itself
# -------------------------------------------------------
selfhost: stage1
	./$(JDA1_BIN) $(JDA1_SRC) jda1_selfhost
	chmod +x jda1_selfhost
	@echo "[selfhost] jda1_selfhost binary ready. Verifying..."
	# Use the self-hosted jda1 to compile hello.jda as final check
	./jda1_selfhost $(HELLO_SRC) hello_sh
	chmod +x hello_sh
	./hello_sh
	@echo "[selfhost] PASS — self-hosting milestone achieved!"

# -------------------------------------------------------
# Basic hello test (original Stage 0 test)
# -------------------------------------------------------
test: jda0
	$(JDA0) $(HELLO_SRC) hello_out
	chmod +x hello_out
	./hello_out

clean:
	rm -f jda0.o jda0 $(JDA1_BIN) jda1_selfhost hello_out hello_s1 hello_sh
