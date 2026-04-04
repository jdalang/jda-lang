# Phase 7 — Native Machine Learning Plan

**Goal**: Replace Python as the ML language by making tensors and autograd native compiler primitives. No runtime graph, no C++ runtime, no CUDA toolkit — just Jda.

**Prerequisite**: Phase 6 complete. Self-hosted compiler with concurrency (spawn, channels, atomics, epoll), 114 conformance tests, self-host converged at 1,787,169 bytes.

---

## Existing Design Work

Substantial design already exists in the codebase (spec-complete, not yet compiled):

| Component | File | Status |
|-----------|------|--------|
| Tensor type & shape system | `ml/tensor.jda` | Designed (9.8KB) |
| Compile-time autograd | `ml/autograd.jda` | Designed (9.4KB) |
| PTX backend (NVIDIA) | `ml/ptx.jda` | Designed (12.8KB) |
| ROCm backend (AMD) | `ml/rocm.jda` | Designed (21.2KB) |
| AVX-512 vectorization | `ml/avx512.jda` | Designed (9.9KB) |
| Neural network layers | `stdlib/ml/nn.jda` | Designed (7.8KB) |
| DataLoader & Dataset | `stdlib/ml/data.jda` | Designed (13.9KB) |
| Metrics (accuracy, F1, etc.) | `stdlib/ml/metrics.jda` | Designed (15.6KB) |
| XOR training demo | `examples/mlp.jda` | Designed (10 lines) |
| JIR vector ops | `ir/jir.jda` | OP_MATMUL, TYPE_VEC defined |

**What needs to be built in the compiler (jda1.jda)**:
1. Floating point types (f32, f64) — lexer, parser, codegen, x86 lowering (SSE/AVX)
2. Tensor type with compile-time shape tracking
3. CPU tensor operations (matmul, elementwise, reductions)
4. AVX-512 vectorization JIR pass
5. `@differentiable` attribute and autograd JIR pass
6. PTX code generation (JIR → PTX text → GPU dispatch via ioctls)
7. ROCm code generation (JIR → RDNA2 ISA → dispatch via KFD ioctls)

---

## What Phase 7 Does NOT Include

These are explicitly deferred:
- **Distributed training** — multi-GPU and multi-node training is post-1.0
- **Quantization** — INT8/FP16 inference optimization is Phase 8+
- **Custom CUDA kernels** — users write Jda, compiler generates GPU code
- **Dynamic shapes** — all tensor shapes must be known at compile time initially
- **Sparse tensors** — dense tensors only for initial release
- **io_uring for data loading** — epoll is sufficient initially
- **TPU/Apple Neural Engine** — NVIDIA and AMD GPUs only

---

## Milestones (in dependency order)

### M1: Floating Point Types

**Target**: f32 and f64 as first-class types in the compiler.

#### Problem
The compiler only handles i64. Every ML operation requires floating point — weights, activations, gradients, loss values are all f32/f64.

#### Solution

**Lexer/Parser**:
- Add `TYPE_F32` and `TYPE_F64` type constants
- Parse float literals: `3.14`, `1e-3`, `0.5f` (f32 suffix), default f64
- Parse type annotations: `let x: f32 = 3.14`

**JIR**:
- Add float-specific opcodes: `OP_FADD`, `OP_FSUB`, `OP_FMUL`, `OP_FDIV`, `OP_FCMP`, `OP_FSQRT`
- Add conversion opcodes: `OP_I2F` (int→float), `OP_F2I` (float→int), `OP_F32_TO_F64`, `OP_F64_TO_F32`
- Float constants stored as i64 bit patterns (IEEE 754)

**x86-64 Lowering**:
- f64: `MOVSD`, `ADDSD`, `SUBSD`, `MULSD`, `DIVSD`, `SQRTSD`, `UCOMISD` (XMM registers)
- f32: `MOVSS`, `ADDSS`, `SUBSS`, `MULSS`, `DIVSS`, `SQRTSS`, `UCOMISS` (XMM registers)
- Calling convention: f32/f64 args in XMM0-XMM7, return in XMM0
- XMM register allocator: separate pool from GPR (XMM0-XMM15, 16 registers)

**Register Allocator Changes**:
- Separate float register pool (XMM0-XMM15)
- Float spills use `MOVSD [RBP-off], XMMn` / `MOVSD XMMn, [RBP-off]`
- Track type of each value to route to correct pool

**Risk**: HIGH. This is the single largest compiler change — touches lexer, parser, type checker, JIR, register allocator, and lowering. Careful incremental testing required.

**Tests**: `float_add.jda`, `float_mul.jda`, `float_div.jda`, `float_cmp.jda`, `float_sqrt.jda`, `float_conv.jda`, `float_print.jda`

---

### M2: Float Printing & Math Builtins

**Target**: Print f32/f64 values, basic math functions.

#### Problem
`print_int` only handles integers. ML training loops need to print loss values. Also need math functions: exp, log, pow, sin, cos, tanh.

#### Solution

**print_float builtin**:
- Grisu2 or simple digit extraction algorithm for f64 → string
- Format: fixed decimal for |x| in [0.001, 1e6], scientific otherwise
- Emit as inline x86 in `lower_print_float`

**Math builtins** (all f64 → f64):
- `exp(x)`: Taylor series or minimax polynomial (12 terms for 1e-15 precision)
- `log(x)`: Range reduction + polynomial (Cephes algorithm)
- `pow(x, y)`: `exp(y * log(x))`
- `sqrt(x)`: x86 `SQRTSD` instruction (exact)
- `sin(x)`, `cos(x)`: Range reduction + Chebyshev polynomial
- `tanh(x)`: `(exp(2x) - 1) / (exp(2x) + 1)`
- `abs(x)`: Clear sign bit with `ANDPD`

These are pure math with no dependencies — emit as inline x86 sequences.

**Tests**: `print_float.jda`, `math_exp.jda`, `math_log.jda`, `math_sqrt.jda`, `math_trig.jda`

---

### M3: Heap-Allocated Tensor Type

**Target**: `Tensor` as a runtime struct with shape metadata and data pointer.

#### Problem
Tensors need contiguous f32/f64 storage with shape information for dispatch. Shapes should be checked at compile time where possible but stored at runtime for dynamic dispatch.

#### Solution

**Runtime representation** (struct, not a language primitive initially):
```
struct Tensor {
    data: &f32       ; pointer to contiguous f32 storage
    ndim: i64        ; number of dimensions (1-4)
    shape: &i64      ; shape[ndim] array
    strides: &i64    ; strides[ndim] for indexing
    len: i64         ; total element count (product of shape)
}
```

**Builtin functions**:
- `tensor_new(shape: &i64, ndim: i64) -> &Tensor` — allocates via mmap, zeroed
- `tensor_fill(t: &Tensor, val: f32)` — fill with constant
- `tensor_randn(t: &Tensor, seed: i64)` — fill with N(0,1) random values (Box-Muller)
- `tensor_get(t: &Tensor, idx: &i64) -> f32` — bounds-checked element access
- `tensor_set(t: &Tensor, idx: &i64, val: f32)` — bounds-checked element store
- `tensor_free(t: &Tensor)` — munmap storage

**Memory layout**: Row-major (C-order). strides[i] = product of shape[i+1..ndim].

**Tests**: `tensor_new.jda`, `tensor_fill.jda`, `tensor_randn.jda`, `tensor_index.jda`

---

### M4: CPU Tensor Operations

**Target**: matmul, elementwise ops, reductions — all on CPU with scalar f64/f32.

#### Problem
Before vectorizing or GPU-offloading, need correct reference implementations for every tensor operation.

#### Solution

**Core operations** (all as Jda library functions, NOT compiler builtins):
```
fn matmul(a: &Tensor, b: &Tensor, out: &Tensor)       ; [M,K] × [K,N] → [M,N]
fn tensor_add(a: &Tensor, b: &Tensor, out: &Tensor)    ; elementwise
fn tensor_sub(a: &Tensor, b: &Tensor, out: &Tensor)
fn tensor_mul(a: &Tensor, b: &Tensor, out: &Tensor)    ; Hadamard product
fn tensor_scale(a: &Tensor, s: f32, out: &Tensor)      ; scalar multiply
fn tensor_sum(a: &Tensor) -> f32                        ; reduce sum
fn tensor_mean(a: &Tensor) -> f32                       ; reduce mean
fn tensor_max(a: &Tensor) -> f32                        ; reduce max
fn tensor_relu(a: &Tensor, out: &Tensor)                ; max(0, x)
fn tensor_sigmoid(a: &Tensor, out: &Tensor)             ; 1/(1+exp(-x))
fn tensor_tanh_t(a: &Tensor, out: &Tensor)              ; tanh(x)
fn tensor_softmax(a: &Tensor, out: &Tensor)             ; along last axis
fn tensor_transpose(a: &Tensor, out: &Tensor)           ; 2D transpose
```

**Matmul implementation**: Triple-nested loop with loop tiling for L1 cache (tile = 32×32 for f32, fits in 32KB L1). This is the scalar reference — M5 will vectorize it.

**Shape validation**: Runtime assertions. `matmul` checks `a.shape[1] == b.shape[0]`. Crash with error message on mismatch.

**Tests**: `matmul_2x2.jda`, `matmul_4x4.jda`, `tensor_add.jda`, `tensor_relu.jda`, `tensor_softmax.jda`, `tensor_transpose.jda`

---

### M5: AVX-512 Vectorization

**Target**: 16× speedup on tensor operations via 512-bit SIMD.

#### Problem
Scalar matmul on [1024,1024] takes ~2 billion FMAs. AVX-512 processes 16 f32s per instruction with fused multiply-add. Theoretical 32× speedup per core.

#### Solution

**Approach 1 — Library-level vectorization (recommended for M5)**:
Write hand-optimized AVX-512 tensor kernels using inline asm blocks.

```jda
fn matmul_avx512(a: &Tensor, b: &Tensor, out: &Tensor) {
    ; 16×16 tile kernel using ZMM registers
    ; Loop over tiles, load 16 floats per VMOVAPS, FMA via VFMADD213PS
    asm volatile {
        in rdi = a.data
        in rsi = b.data
        in rdx = out.data
        ---
        ; EVEX-encoded instructions emitted as raw bytes
    }
}
```

**New x86 instructions to support**:
- `VMOVAPS` (ZMM load/store, 512-bit aligned): EVEX prefix + 0F 28/29
- `VBROADCASTSS` (broadcast f32 to all 16 lanes): EVEX + 0F38 18
- `VFMADD213PS` (fused multiply-add): EVEX + 0F38 A8
- `VXORPS` (zero register): EVEX + 0F 57
- `VMOVUPS` (unaligned load/store): EVEX + 0F 10/11

**EVEX encoding**: 4-byte prefix (62h + P0 + P1 + P2) before opcode. ZMM0-ZMM31 accessible. The compiler needs to emit these raw bytes — no assembler.

**Approach 2 — Compiler auto-vectorization pass (deferred to M5b)**:
JIR pass that detects tensor loops and rewrites with vector ops. Complex and fragile — defer until hand-written kernels prove the performance.

**Benchmark target**: matmul [1024,1024] in <10ms on modern x86 (theoretical: 2B FMAs / 128 GFLOPS ≈ 15ms).

**Tests**: `avx512_matmul.jda`, `avx512_add.jda`, benchmark comparison vs scalar

---

### M6: Compile-Time Autograd

**Target**: `@differentiable` attribute triggers compiler-generated backward pass.

#### Problem
PyTorch builds a runtime computation graph, allocating nodes for every operation. This adds overhead and prevents ahead-of-time optimization. Jda should generate the backward pass at compile time — the gradient code is plain Jda that goes through the same optimizer.

#### Solution

**Compiler pass** (operates on JIR, after optimization, before lowering):

1. Mark functions with `@differentiable` attribute (parsed in lexer as decorator)
2. For each marked function, clone the JIR and transform:
   - Walk instructions in reverse (reverse-mode AD)
   - For each instruction, emit its derivative:

| Forward op | Backward rule |
|-----------|---------------|
| `c = a + b` | `grad_a += grad_c; grad_b += grad_c` |
| `c = a - b` | `grad_a += grad_c; grad_b -= grad_c` |
| `c = a * b` | `grad_a += grad_c * b; grad_b += grad_c * a` |
| `c = a / b` | `grad_a += grad_c / b; grad_b -= grad_c * a / (b*b)` |
| `c = matmul(a, b)` | `grad_a += matmul(grad_c, bT); grad_b += matmul(aT, grad_c)` |
| `c = relu(a)` | `grad_a += grad_c * (a > 0)` |
| `c = exp(a)` | `grad_a += grad_c * c` |
| `c = log(a)` | `grad_a += grad_c / a` |
| `c = tanh(a)` | `grad_a += grad_c * (1 - c*c)` |
| `c = sum(a)` | `grad_a += broadcast(grad_c)` |

3. Generate function `<name>_grad(inputs, grad_output) -> grad_inputs`
4. The generated gradient function goes through the same optimization pipeline (constant folding, DCE, register allocation)

**Key advantage**: No runtime graph allocation. The backward pass is AOT-compiled code.

**Tests**: `autograd_add.jda`, `autograd_mul.jda`, `autograd_chain.jda`, `autograd_matmul.jda`, `autograd_relu.jda`

---

### M7: Neural Network Library

**Target**: Train a 2-layer MLP on XOR in pure Jda.

#### Problem
Need standard building blocks: layers, loss functions, optimizers. These are pure Jda library code built on M1-M6.

#### Solution

**Layers** (plain Jda structs with forward/backward):
```jda
struct Linear {
    weight: &Tensor   ; [out_features, in_features]
    bias: &Tensor      ; [out_features]
    grad_w: &Tensor    ; accumulated weight gradient
    grad_b: &Tensor    ; accumulated bias gradient
    input_cache: &Tensor ; saved for backward pass
}

fn linear_forward(l: &Linear, x: &Tensor, out: &Tensor) {
    matmul(x, l.weight, out)    ; out = x @ W^T
    tensor_add(out, l.bias, out) ; out += bias
    tensor_copy(x, l.input_cache) ; save for backward
}

fn linear_backward(l: &Linear, grad_out: &Tensor, grad_in: &Tensor) {
    ; grad_w = grad_out^T @ input_cache
    ; grad_b = sum(grad_out, axis=0)
    ; grad_in = grad_out @ weight
}
```

**Activations**: ReLU, Sigmoid, Tanh, Softmax — each with forward and backward.

**Loss functions**:
- MSE: `(1/n) * sum((pred - target)^2)`
- Cross-entropy: `-sum(target * log(softmax(pred)))`

**Optimizer — SGD**:
```jda
fn sgd_step(params: &Tensor, grads: &Tensor, lr: f32) {
    ; params -= lr * grads
    tensor_scale(grads, lr, grads)
    tensor_sub(params, grads, params)
}
```

**Optimizer — Adam** (with momentum and adaptive learning rate):
```jda
struct Adam {
    m: &Tensor    ; first moment
    v: &Tensor    ; second moment
    beta1: f32    ; 0.9
    beta2: f32    ; 0.999
    eps: f32      ; 1e-8
    t: i64        ; step count
}
```

**XOR demo** (the capstone):
```jda
fn main() {
    let x = tensor_from([0,0, 0,1, 1,0, 1,1], [4,2])   ; inputs
    let y = tensor_from([0, 1, 1, 0], [4,1])             ; targets
    let l1 = linear_new(2, 16)                            ; 2→16
    let l2 = linear_new(16, 1)                            ; 16→1
    let lr = 0.01
    let epoch = 0
    loop epoch < 1000 {
        let h = linear_forward(l1, x)
        let h2 = relu(h)
        let out = linear_forward(l2, h2)
        let loss = mse_loss(out, y)
        backward(loss)
        sgd_step(l1, lr)
        sgd_step(l2, lr)
        epoch = epoch + 1
    }
    print_float(loss)  ; should be < 0.01
}
```

**Tests**: `xor_train.jda`, `linear_forward.jda`, `relu_backward.jda`, `sgd_step.jda`

---

### M8: PTX Backend (NVIDIA GPU)

**Target**: Offload matmul to NVIDIA GPU via direct ioctls — no CUDA toolkit.

#### Problem
CUDA requires nvcc (C++ compiler) and the CUDA runtime library. Jda should compile directly to PTX assembly and dispatch to the GPU via the NVIDIA kernel driver.

#### Solution

**Architecture**:
```
Jda source → JIR → PTX text → assemble (cuModuleLoad) → launch (cuLaunchKernel)
                                    ↓
                          NVIDIA driver ioctls (/dev/nvidia0)
```

**PTX code generation** (new pass in jda1.jda):
1. Detect `@gpu` annotated functions
2. Lower JIR to PTX assembly text (string buffer)
3. PTX instructions: `ld.global.f32`, `st.global.f32`, `fma.rn.f32`, `add.f32`, `mul.f32`
4. Thread indexing: `%tid.x`, `%ctaid.x`, `%ntid.x`

**GPU dispatch** (runtime, using raw syscalls):
1. Open `/dev/nvidiactl` and `/dev/nvidia0` (syscall 2 = open)
2. Allocate GPU memory: `ioctl(fd, NV_ESC_RM_ALLOC_MEMORY, ...)`
3. Copy host → device: `ioctl(fd, NV_ESC_RM_MEMCPY_H2D, ...)`
4. Load PTX module: `ioctl(fd, NV_ESC_RM_LOAD_MODULE, ...)`
5. Launch kernel: `ioctl(fd, NV_ESC_RM_LAUNCH_KERNEL, ...)`
6. Copy device → host: `ioctl(fd, NV_ESC_RM_MEMCPY_D2H, ...)`
7. Free GPU memory

**Matmul kernel** (16×16 tiled, shared memory):
```ptx
.visible .entry sgemm_16x16(
    .param .u64 A, .param .u64 B, .param .u64 C,
    .param .u32 M, .param .u32 N, .param .u32 K
) {
    .shared .f32 As[16][16];
    .shared .f32 Bs[16][16];
    ; ... tile loop with fma.rn.f32
}
```

**Risk**: VERY HIGH. NVIDIA driver ioctls are undocumented and change between driver versions. Fallback: use CUDA driver API (libcuda.so) via function pointer loads from dlopen.

**Tests**: `gpu_matmul.jda` (requires NVIDIA GPU in CI), `gpu_memcpy.jda`

---

### M9: ROCm Backend (AMD GPU)

**Target**: Same capabilities as M8 but for AMD GPUs via KFD (Kernel Fusion Driver).

#### Solution

Similar to M8 but using:
- `/dev/kfd` and `/dev/dri/renderD128` device files
- KFD ioctls: `KFD_IOC_CREATE_QUEUE`, `KFD_IOC_ALLOC_MEMORY_OF_GPU`, `KFD_IOC_SUBMIT_QUEUE`
- RDNA2/RDNA3 ISA (GFX10/GFX11) instead of PTX
- Instruction encoding: 32-bit instruction words (VOP2, VOP3, SMEM, FLAT formats)

**Risk**: HIGH. KFD interface is more stable than NVIDIA ioctls but still evolving.

---

### M10: Transformer Demo

**Target**: Train a small transformer (GPT-2-like, ~1M params) in pure Jda.

#### Components needed (all built on M1-M9):
- Multi-head attention: Q, K, V projections + scaled dot-product attention
- Layer normalization
- Position embeddings
- Tokenizer (BPE or character-level)
- Training loop with Adam optimizer

**Model**: 4 layers, 4 heads, d_model=128, d_ff=512, vocab=256 (byte-level).
**Dataset**: Shakespeare text (~1MB).
**Target**: Generate coherent English text after training.

This is the capstone that proves Jda can replace Python for real ML workloads.

---

## Projected Progression

| Milestone | Lines changed | Key deliverable |
|-----------|--------------|-----------------|
| M1: Float types | ~800 | `let x: f32 = 3.14; let y = x * x` |
| M2: Float printing & math | ~400 | `print_float(exp(1.0))` → 2.718281... |
| M3: Tensor type | ~300 | `tensor_new([1024,1024])`, get/set |
| M4: CPU tensor ops | ~500 | `matmul([M,K], [K,N])` correct |
| M5: AVX-512 | ~600 | matmul 16× faster |
| M6: Autograd | ~700 | `@differentiable fn loss()` generates `loss_grad()` |
| M7: NN library | ~500 | XOR trains to <0.01 loss |
| M8: PTX backend | ~1000 | GPU matmul via ioctls |
| M9: ROCm backend | ~800 | AMD GPU matmul |
| M10: Transformer | ~400 | Generate English text |

---

## Execution Strategy

- **M1 is the critical path** — everything else depends on floating point. Ship M1 first, then M2-M4 can proceed quickly.
- M3 and M4 are pure library code (Jda programs, not compiler changes) — fast to iterate.
- M5 (AVX-512) can be developed in parallel with M6 (autograd) since they touch different parts of the pipeline.
- M7 depends on M4 + M6.
- M8 and M9 are independent of each other (NVIDIA vs AMD).
- M10 depends on everything.
- Each milestone = separate branch + PR, full test suite + self-host convergence.

## Verification Protocol (every milestone)

1. All conformance tests pass (existing + new)
2. Self-host convergence: `jda1_sh2 == jda1_sh3`
3. Milestone-specific benchmark (where applicable)
4. Update `docs/phase7-plan.md` with results
5. No regression on Phase 5 performance benchmarks
