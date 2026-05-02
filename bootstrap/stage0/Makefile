# Jda Build System
#
# Default build uses the self-hosted bootstrap compiler (no NASM required):
#   make stage1          # jda1-bootstrap compiles jda1.jda → jda1
#
# Legacy build from assembly (requires NASM):
#   make jda0            # assemble jda0 from NASM source
#   make stage1-from-asm # jda0 compiles jda1.jda → jda1
#
# Self-host verification:
#   make selfhost        # full 4-stage pipeline, verifies convergence

NASM      = nasm
LD        = ld
NASMFLAGS = -f elf64 -g -F dwarf
PYTHON    = python3

# Bootstrap compiler (self-hosted, checked into git)
BOOTSTRAP = ../bin/jda1-bootstrap

# Legacy assembler
JDA0      = ./jda0

JDA1_SRC  = ../stage1/jda1.jda
JDA1_BIN  = jda1
HELLO_SRC = ../../examples/hello.jda

# Generated files (for legacy jda0 build only)
GEN_CONST = jda0_constants.asm
GEN_STRUCT = jda0_structs.asm

# -------------------------------------------------------
# Default: build jda1 from bootstrap compiler (no NASM)
# -------------------------------------------------------
all: stage1

stage1: $(BOOTSTRAP)
	$(BOOTSTRAP) $(JDA1_SRC) $(JDA1_BIN)
	chmod +x $(JDA1_BIN)
	@echo "[stage1] jda1 compiled from bootstrap. Ready."

# -------------------------------------------------------
# Self-host verification: 4-stage pipeline
# Proves jda1 is a fixed point (stage3 == stage4)
# -------------------------------------------------------
selfhost: stage1
	./$(JDA1_BIN) $(JDA1_SRC) jda1_sh2
	chmod +x jda1_sh2
	./jda1_sh2 $(JDA1_SRC) jda1_sh3
	chmod +x jda1_sh3
	./jda1_sh3 $(JDA1_SRC) jda1_sh4
	chmod +x jda1_sh4
	cmp jda1_sh3 jda1_sh4
	@echo "[selfhost] CONVERGED — jda1_sh3 == jda1_sh4"

# -------------------------------------------------------
# Test: compile and run hello.jda
# -------------------------------------------------------
test: stage1
	./$(JDA1_BIN) $(HELLO_SRC) hello_test
	chmod +x hello_test
	./hello_test
	@echo "[test] PASS"

# -------------------------------------------------------
# Update bootstrap: replace bootstrap binary with current
# self-hosted output after verifying convergence
# -------------------------------------------------------
update-bootstrap: selfhost
	cp jda1_sh3 $(BOOTSTRAP)
	cd ../bin && shasum -a 256 jda1-bootstrap > CHECKSUMS.new && mv CHECKSUMS.new CHECKSUMS
	@echo "[update-bootstrap] Bootstrap binary updated. Commit bootstrap/bin/."

# -------------------------------------------------------
# Legacy: build jda0 from NASM assembly (requires nasm + ld)
# -------------------------------------------------------
generate-constants: $(GEN_CONST)

$(GEN_CONST):
	@echo "[gen] Generating jda0 constants from specification..."
	$(PYTHON) ../../tools/generate_jda0_constants.py
	@echo "[gen] Validating generated constants..."
	$(PYTHON) ../../tools/validate_jda0_constants.py
	@echo "[gen] Constants generated and validated successfully"

generate-structs: $(GEN_STRUCT)

$(GEN_STRUCT):
	@echo "[gen] Generating jda0 struct offsets from specification..."
	$(PYTHON) ../../tools/generate_jda0_structs.py
	@echo "[gen] Validating generated struct layouts..."
	$(PYTHON) ../../tools/validate_jda0_structs.py
	@echo "[gen] Struct offsets generated and validated successfully"

generate-all: generate-constants generate-structs
	@echo "[gen] All code generation complete!"

jda0: jda0.o
	$(LD) -o jda0 jda0.o

jda0.o: jda0.asm $(GEN_CONST) $(GEN_STRUCT)
	$(NASM) $(NASMFLAGS) -o jda0.o jda0.asm

stage1-from-asm: jda0
	$(JDA0) $(JDA1_SRC) $(JDA1_BIN)
	chmod +x $(JDA1_BIN)
	@echo "[stage1-from-asm] jda1 compiled from jda0 (legacy)."

# -------------------------------------------------------
# Clean
# -------------------------------------------------------
clean:
	rm -f jda0.o jda0 $(JDA1_BIN) jda1_sh* hello_test
	rm -f $(GEN_CONST) $(GEN_STRUCT)
	@echo "[clean] Removed build artifacts"

.PHONY: all stage1 selfhost test update-bootstrap generate-constants generate-structs generate-all stage1-from-asm clean
