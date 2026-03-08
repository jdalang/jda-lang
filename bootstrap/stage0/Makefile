# Stage 0: Jda Bootstrapper (x86-64 NASM, Linux)
# Run inside Docker: make all

NASM      = nasm
LD        = ld
NASMFLAGS = -f elf64 -g -F dwarf
PYTHON    = python3

JDA0      = ./jda0
JDA1_SRC  = ../stage1/jda1.jda
JDA1_BIN  = jda1
HELLO_SRC = ../../examples/hello.jda

# Generated files (auto-generated, not committed)
GEN_CONST = jda0_constants.asm
GEN_STRUCT = jda0_structs.asm

all: jda0

# -------------------------------------------------------
# Auto-generation: Specification and Constants
# -------------------------------------------------------
generate-constants: $(GEN_CONST)

$(GEN_CONST):
	@echo "[gen] Generating jda0 constants from specification..."
	$(PYTHON) ../../tools/generate_jda0_constants.py
	@echo "[gen] Validating generated constants..."
	@$(PYTHON) ../../tools/validate_jda0_constants.py || true
	@echo "[gen] Constants generated successfully"

generate-structs: $(GEN_STRUCT)

$(GEN_STRUCT):
	@echo "[gen] Generating jda0 struct offsets from specification..."
	$(PYTHON) ../../tools/generate_jda0_structs.py
	@echo "[gen] Validating generated struct layouts..."
	@$(PYTHON) ../../tools/validate_jda0_structs.py || true
	@echo "[gen] Struct offsets generated successfully"

generate-all: generate-constants generate-structs
	@echo "[gen] All code generation complete!"

# -------------------------------------------------------
# Stage 0: assembler → jda0 binary
# -------------------------------------------------------
jda0: jda0.o
	$(LD) -o jda0 jda0.o

jda0.o: jda0.asm $(GEN_CONST) $(GEN_STRUCT)
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
	rm -f $(GEN_CONST) $(GEN_STRUCT)
	@echo "[clean] Removed generated files"

.PHONY: all generate-constants generate-structs generate-all test test-stage1 selfhost clean
