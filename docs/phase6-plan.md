# Phase 6 — Concurrency Runtime Plan

**Goal**: Match Go's concurrency with deterministic performance (no GC). Jda programs should be able to spawn millions of lightweight threads and communicate via channels — all with compile-time memory safety.

**Prerequisite**: Phase 5 complete. Self-hosted compiler with enums, generics, CTRC, linear types, arenas, and performance within 3.7x of C -O2 on fib35. Self-host converged at 1,697,358 bytes. 82 conformance tests.

---

## Existing Infrastructure

Substantial design work already exists in the codebase:

| Component | File | Status |
|-----------|------|--------|
| J-Thread descriptor (JThread struct) | `concurrency/jthread.jda` | Designed, not compiled |
| Context switch (inline asm) | `concurrency/jthread.jda:100-130` | Designed, needs compiler support |
| Work-stealing scheduler | `concurrency/jthread.jda:134-179` | Designed, needs atomics |
| Lock-free channels (MPSC) | `concurrency/channel.jda` | Designed, needs atomics + generics |
| TCP sockets (non-blocking + yield) | `stdlib/net/tcp.jda` | Designed, needs jthread_yield |
| UDP sockets + multicast | `stdlib/net/udp.jda` | Designed, needs jthread_yield |
| HTTP/1.1 parser (zero-copy) | `stdlib/net/http.jda` | Designed |
| WebSocket (RFC 6455) | `stdlib/net/ws.jda` | Designed, needs tcp.jda |
| Page allocator (mmap/munmap) | `mem/page_alloc.jda` | Designed |
| Region allocator (arenas) | `mem/region.jda` | Designed |
| Process management (fork/exec/signals) | `stdlib/process.jda` | Designed |

**What needs to be built in the compiler (jda1.jda)**:
1. Atomic operations — new JIR opcodes + x86 lowering (LOCK prefix)
2. `asm volatile {}` blocks — inline assembly support for context switch
3. `spawn` keyword — lexer/parser/codegen desugaring
4. OS thread creation — `clone()` syscall for M:N scheduler
5. epoll integration — event-driven I/O for `jthread_yield_until_writable()`
6. Deadlock detection — cycle detection on blocked thread graph

---

## What Phase 6 Does NOT Include

These are explicitly deferred:
- **Closures / captured variables** — `spawn` will initially require a function pointer + argument, not a full closure with captures
- **Async/await syntax** — channels + yield are sufficient; async sugar is Phase 8
- **Distributed channels** — network-transparent channels are post-1.0
- **NUMA-aware scheduling** — single-socket scheduling first
- **io_uring** — epoll is simpler and sufficient for initial release

---

## Milestones (in dependency order)

### M1: Atomic Operations ✅

**Completed**: April 3, 2026

**What was done**:
1. Added 5 new JIR opcodes: OP_ATOMIC_LOAD(35), OP_ATOMIC_STORE(36), OP_ATOMIC_CAS(37), OP_ATOMIC_ADD(38), OP_RDTSC(39)
2. Added builtin function name recognition in both `codegen_call_inline` and `live_codegen_call_inline` for: `atomic_load`, `atomic_store`, `atomic_cmpxchg`, `atomic_fetch_add`, `rdtsc`
3. Added DCE handling (operand marking + side-effect marking) for all 5 opcodes
4. Added `lower_fn_mark_uses_instr` handling for all 5 opcodes
5. Added `lower_instr_atomic` function with x86-64 lowering:
   - `OP_ATOMIC_LOAD`: `MOV r, [addr]` (x86 loads are naturally acquire-ordered)
   - `OP_ATOMIC_STORE`: `XCHG [addr], r` (implicit LOCK prefix, full barrier)
   - `OP_ATOMIC_CAS`: `LOCK CMPXCHG [RDI], RCX` (push/pop pattern for safe register setup)
   - `OP_ATOMIC_ADD`: `LOCK XADD [RDI], RCX` (push/pop pattern)
   - `OP_RDTSC`: `RDTSC; SHL RDX,32; OR RAX,RDX` (combine EDX:EAX into 64-bit)
6. All 86 conformance tests pass (4 new: `atomic_load_store`, `atomic_cas`, `atomic_fetch_add`, `rdtsc_basic`)
7. Self-host converged at 1,711,980 bytes

**Impact**: Provides the primitive building blocks needed for lock-free channels (M5) and the work-stealing scheduler (M6). No existing codegen changed — the new opcodes are only emitted when user code calls the builtin functions.

---

### M2: Inline Assembly Blocks ✅

**Target**: Support `asm volatile { ... }` blocks for the context switch and future low-level primitives.

#### Problem
`jthread_switch()` requires saving/restoring 8 registers via inline assembly. The compiler currently only handles `asm { out var = rsi }` for argv access — it cannot emit arbitrary x86 instructions from Jda source.

#### Solution: Structured Inline Asm

Support the syntax already used in `jthread.jda`:

```jda
fn jthread_switch(from: &mut JThread, to: &mut JThread) {
    asm volatile {
        in  rdi = from      ; bind rdi to `from` variable
        in  rsi = to        ; bind rsi to `to` variable
        ---
        mov  [rdi + 8],  rbp
        mov  [rdi + 24], rbx
        ; ... (instruction stream)
        jmp  [rsi + 16]
        .resume:
    }
}
```

**Compiler changes**:
1. **Lexer**: Recognize `asm` keyword (already TK_ASM), add `volatile` as modifier
2. **Parser**: Parse `asm volatile { in/out bindings --- instruction lines }` into a new AST node
3. **Codegen**: Emit a new `OP_ASM_BLOCK` JIR instruction containing:
   - Input bindings (variable → register mapping)
   - Raw instruction bytes (assembled at compile time)
   - Output bindings (register → variable mapping)
4. **x86 Assembler (mini)**: A small assembler embedded in the lowering pass that handles:
   - `mov [reg + imm], reg` — MOV with displacement
   - `mov reg, [reg + imm]` — MOV from memory
   - `lea reg, [rip + label]` — RIP-relative LEA
   - `jmp [reg + imm]` — indirect jump
   - Local labels (`.resume:`) resolved within the block
   - Named registers: rax, rbx, rcx, rdx, rsi, rdi, rbp, rsp, r8-r15
5. **Register clobber**: `asm volatile` clobbers all registers — emit save_pool/restore_pool around it (unless the asm block manages its own save/restore, as jthread_switch does)

**Approach**: Start with a minimal instruction set — just enough for `jthread_switch`. Extend as needed. The mini-assembler is a table-driven encoder, not a full assembler.

**Tests**: `asm_mov_reg_reg`, `asm_mov_mem`, `asm_label_jmp`, `asm_volatile_clobber`

**Risk**: MEDIUM. Inline asm interacts with register allocation. Must ensure the register allocator knows which registers the asm block uses/clobbers. Mitigation: treat all `asm volatile` blocks as full-clobber (save everything).

---

### M3: spawn Keyword + Thread Stacks (~250 lines in jda1.jda) ✅

**Target**: `spawn expr` creates a new J-Thread that runs `expr` and returns a thread ID.

#### Problem
Users need a way to create lightweight threads. The syntax `spawn { work() }` must allocate a stack, create a JThread descriptor, and enqueue it on the scheduler.

#### Solution

**Syntax**:
```jda
let tid = spawn work()              ; spawn a function call
let tid = spawn compute(x, y)      ; spawn with arguments
```

Phase 6 supports spawning function calls only (not arbitrary blocks — that requires closures).

**Compiler changes**:
1. **Lexer**: Add `TK_SPAWN` token type
2. **Parser**: Parse `spawn <call-expr>` — the expression after spawn must be a function call
3. **Codegen**: Desugar to:
   ```
   ; Allocate stack
   v1 = OP_ALLOC(JTHREAD_STACK_PAGES * 4096)
   ; Compute stack top (stack grows down)
   v2 = OP_ADD(v1, JTHREAD_STACK_PAGES * 4096)
   v3 = OP_SUB(v2, 8)
   ; Store return address (thread_exit trampoline) at top of stack
   OP_STORE(v3, &jthread_exit)
   ; Create JThread struct on current stack
   ; Set rsp=v3, rip=<target_fn>, state=JSTATE_READY
   ; Call scheduler_enqueue()
   ```
4. **Thread exit trampoline**: When the spawned function returns, it hits the trampoline which calls `jthread_exit()` to mark the thread DONE and yield.
5. **Argument passing**: For `spawn f(a, b)`, store arguments on the new thread's stack before setting RSP. The thread entry stub pops them into registers before calling `f`.

**Tests**: `spawn_basic` (spawn + join via channel), `spawn_many` (spawn 1000 threads), `spawn_return_tid`

**Risk**: MEDIUM. Stack setup must exactly match the calling convention. Off-by-one in RSP alignment causes SIGSEGV. Mitigation: test with simple functions first, then increase complexity.

---

### M4: Single-Threaded Scheduler (~200 lines in jda1.jda) ✅

**Target**: A working cooperative scheduler on a single OS thread. Spawn, yield, and resume J-Threads.

#### Problem
Before tackling M:N scheduling with OS threads, get the core scheduler loop working on one thread. This validates the context switch, spawn, and yield without the complexity of work-stealing.

#### Solution

**Global scheduler state** (allocated in main()):
```jda
struct Scheduler {
    current:   *JThread          ; currently running thread
    ready:     [4096]JThread     ; circular queue of ready threads
    head:      i64
    tail:      i64
    main_ctx:  JThread           ; context for the main "thread"
}
```

**Key functions**:
- `sched_init()` — allocate scheduler, set up main context
- `sched_enqueue(t)` — push to ready queue tail
- `sched_yield()` — save current, pick next from ready queue head, switch
- `sched_run()` — scheduler loop: pick next ready thread, switch to it, repeat until all DONE
- `jthread_exit()` — mark current DONE, free stack, yield to next

**Cooperative model**: Threads must call `jthread_yield()` to allow other threads to run. No preemption (preemptive scheduling deferred to M5+).

**Demo program**:
```jda
fn worker(id: i64) {
    print_int(id)
    jthread_yield()
    print_int(id)
}

fn main() {
    sched_init()
    spawn worker(1)
    spawn worker(2)
    spawn worker(3)
    sched_run()   ; runs until all threads complete
}
; Output: 1 2 3 1 2 3
```

**Tests**: `sched_round_robin`, `sched_yield_order`, `sched_many_threads`, `sched_nested_spawn`

**Risk**: LOW-MEDIUM. Single-threaded means no data races in the scheduler itself. The main risk is context switch correctness — validated in M2.

---

### M5: Channels (~150 lines in jda1.jda) ✅

**Target**: Lock-free MPSC channels for inter-thread communication.

#### Depends on: M1 (atomics), M4 (scheduler + yield)

#### Problem
Threads need to communicate. Shared mutable state is forbidden by the ownership model, so channels are the only primitive.

#### Solution

Implement `concurrency/channel.jda` as a compilable Jda library. The design is already complete — this milestone is about making it compile and pass tests.

**Key work**:
1. Ensure generic monomorphization works for `Channel<i64>`, `Channel<*i8>`, etc.
2. Wire `chan_send` / `chan_recv` to call `jthread_yield()` when blocking
3. Ownership transfer: `chan_send(ch, val)` moves `val` — compiler must enforce this
4. `chan_close()` wakes all blocked receivers

**Bounded channels** (ring buffer with power-of-2 capacity):
- `chan_new<i64>(64)` — 64-slot buffer
- Send blocks (yields) when full
- Recv blocks (yields) when empty

**Tests**: `chan_send_recv`, `chan_buffered`, `chan_close_wakes`, `chan_ownership_transfer`, `chan_producer_consumer`

**Risk**: LOW. The channel implementation is straightforward given working atomics and yield. The main risk is generic monomorphization correctness for channel types.

---

### M6: OS Thread Pool + M:N Scheduling (~400 lines in jda1.jda) ✅

**Target**: Multiple OS threads running J-Threads in parallel, with work-stealing.

#### Depends on: M4 (single-threaded scheduler), M1 (atomics)

#### Problem
A single-OS-thread scheduler can't use multiple CPU cores. Real concurrency requires N OS threads, each running a scheduler loop, with work-stealing to balance load.

#### Solution

**OS thread creation via clone()**:
```
; Linux clone() syscall
; rax = 56 (SYS_CLONE)
; rdi = flags (CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND | CLONE_THREAD)
; rsi = child_stack (top of new stack)
; rdx = parent_tid_ptr
; r10 = child_tid_ptr
; r8  = tls
```

Flags: `CLONE_VM | CLONE_FS | CLONE_FILES | CLONE_SIGHAND | CLONE_THREAD | CLONE_SYSVSEM` = `0x10F00`

**Architecture**:
1. At startup, detect CPU count via `sched_getaffinity()` (syscall 204)
2. Create N-1 OS threads via `clone()` (main thread is thread 0)
3. Each OS thread runs `worker_loop()`:
   ```
   fn worker_loop(core_id: i64) {
       loop {
           match sched_next(core_id) {
               some(t) => switch_to(t)
               none    => steal_or_park()
           }
       }
   }
   ```
4. **Per-core run queues**: Each OS thread has its own deque (push to tail, pop from tail)
5. **Work-stealing**: Idle threads steal from the head of a random victim's deque
6. **Parking**: If no work anywhere, OS thread calls `futex(FUTEX_WAIT)` to sleep; woken by `futex(FUTEX_WAKE)` when new work is enqueued

**Thread-local storage**: Use a dedicated register (R14 or FS segment) to store the current core ID, avoiding a syscall per scheduler operation. Alternative: use the stack address to identify which OS thread we're on (each OS thread's stack is at a known base address).

**Tests**: `mt_spawn_parallel`, `mt_work_stealing`, `mt_channel_cross_thread`, `mt_futex_park_wake`

**Risk**: HIGH. Multi-threaded code is where subtle bugs hide. Data races in the scheduler, ABA problems in work-stealing, stack corruption from clone(). Mitigation:
- Extensive logging mode (compile-time flag) that traces every context switch
- Start with N=2 threads before scaling to N=cores
- Run every test 100x to surface intermittent failures

---

### M7: I/O Integration (epoll) (~250 lines in jda1.jda) ✅

**Target**: Non-blocking I/O that yields to the scheduler instead of blocking the OS thread.

#### Depends on: M6 (OS threads), M4 (yield)

#### Problem
`tcp.jda` calls `jthread_yield()` when accept/read/write returns EAGAIN, but this is a spin-wait — it yields and retries immediately, wasting CPU. Real async I/O needs event notification.

#### Solution: epoll Integration

**Syscalls**:
- `epoll_create1(flags)` — syscall 291
- `epoll_ctl(epfd, op, fd, event)` — syscall 233
- `epoll_wait(epfd, events, maxevents, timeout)` — syscall 232

**Architecture**:
1. One epoll instance per OS thread (or one global — simpler)
2. When a J-Thread gets EAGAIN:
   - Register the fd with epoll (EPOLLIN for read, EPOLLOUT for write)
   - Set J-Thread state to JSTATE_BLOCKED
   - Store the J-Thread pointer in epoll event data
   - Yield to scheduler
3. Scheduler loop includes an epoll_wait(timeout=0) between context switches
4. When epoll reports an fd is ready, move the associated J-Thread back to JSTATE_READY

**New functions**:
- `jthread_yield_until_readable(fd)` — register EPOLLIN, block, yield
- `jthread_yield_until_writable(fd)` — register EPOLLOUT, block, yield
- `io_poll()` — called by scheduler, returns newly-ready threads

**Impact on tcp.jda**: The existing `jthread_yield()` calls in accept/read/write become `jthread_yield_until_readable(fd)` or `jthread_yield_until_writable(fd)`. Minimal code changes.

**Tests**: `epoll_tcp_echo`, `epoll_accept_yield`, `epoll_concurrent_connections`

**Risk**: MEDIUM. epoll semantics (edge-triggered vs level-triggered, EPOLLONESHOT) can cause missed events. Start with level-triggered (simpler, no missed events).

---

### M8: Deadlock Detection (~150 lines in jda1.jda) ✅

**Target**: Detect when all J-Threads are blocked (waiting on channels or I/O) with no progress possible.

#### Depends on: M5 (channels), M7 (I/O)

#### Problem
If thread A waits on channel from B, and B waits on channel from A, both are JSTATE_BLOCKED and will never be woken. The program hangs silently.

#### Solution: Cycle Detection in Blocked Thread Graph

**When to check**: When the scheduler has zero READY threads and all threads are BLOCKED.

**Algorithm**:
1. Build a wait-for graph: for each BLOCKED thread, record what it's waiting on (channel, fd)
2. For channel waits: if the channel's only potential sender is also BLOCKED, there's a deadlock
3. For the simple case (all threads blocked, no I/O pending): print diagnostic and exit with error

**Diagnostic output**:
```
DEADLOCK: all 3 J-Threads are blocked
  Thread 1: blocked on chan_recv (channel 0x7f...)
  Thread 2: blocked on chan_recv (channel 0x7f...)
  Thread 3: blocked on chan_recv (channel 0x7f...)
No thread can make progress. Aborting.
```

**Simpler initial version**: Skip the full graph analysis. Just detect "all threads BLOCKED, nothing in epoll" — this catches the common case.

**Tests**: `deadlock_simple`, `deadlock_channel_cycle`, `deadlock_false_negative_io`

**Risk**: LOW. Deadlock detection is advisory — false negatives (missed deadlocks) are acceptable initially. False positives (killing a program that would eventually make progress) must be avoided.

---

## Execution Order & Dependencies

```
M1 (atomics) ──────────┬─── M2 (inline asm)
                        │          │
                        │    M3 (spawn + stacks)
                        │          │
                        ├─── M4 (single-thread scheduler)
                        │          │
                        ├─── M5 (channels)
                        │          │
                        │    M6 (OS threads + M:N)
                        │          │
                        │    M7 (epoll I/O)
                        │          │
                        └─── M8 (deadlock detection)
```

**Critical path**: M1 → M2 → M3 → M4 → M6 → M7

**Parallel track**: M5 (channels) can be developed alongside M3/M4 once M1 is done.

**M8 is independent**: Can be added at any time after M4.

---

## Projected Progression

| Milestone | Lines Changed | What It Unlocks |
|-----------|---------------|-----------------|
| M1 | ~200 | Lock-free data structures, timestamps |
| M2 | ~300 | Context switch, future low-level primitives |
| M3 | ~250 | `spawn f()` creates green threads |
| M4 | ~200 | Cooperative multitasking on 1 core |
| M5 | ~150 | Inter-thread communication |
| M6 | ~400 | True parallelism across CPU cores |
| M7 | ~250 | Efficient async I/O (TCP/UDP servers) |
| M8 | ~150 | Safety net for hung programs |
| **Total** | **~1900** | **Full concurrency runtime** |

---

## Demo Programs

### After M4 (single-threaded cooperative):
```jda
fn producer(ch: &Channel<i64>) {
    let i = 0
    loop i < 10 {
        chan_send(ch, i)
        i = i + 1
    }
    chan_close(ch)
}

fn consumer(ch: &Channel<i64>) {
    loop {
        match chan_recv(ch) {
            ok(v)  => print_int(v)
            err(_) => ret
        }
    }
}

fn main() {
    sched_init()
    let ch = chan_new<i64>(8)
    spawn producer(&ch)
    spawn consumer(&ch)
    sched_run()
}
```

### After M7 (async TCP echo server):
```jda
fn handle_client(stream: own TcpStream) {
    let buf = [0i8; 4096]
    loop {
        let n = stream.read(buf, 4096)
        if n <= 0 { break }
        stream.write(buf, n)
    }
    stream.close()
}

fn main() {
    sched_init_mt()   ; multi-threaded scheduler
    let listener = TcpListener::bind("0.0.0.0", 8080)?
    loop {
        let stream = listener.accept()?
        spawn handle_client(stream)   ; one green thread per connection
    }
}
```

---

## Self-Hosting Strategy

Same as previous phases — every milestone must maintain self-host convergence:

1. Add the feature to jda1.jda
2. Verify: `jda1 → jda1_sh2 → jda1_sh3`, confirm `sh2 == sh3`
3. All conformance tests still pass
4. Update bootstrap binary

**Key difference from Phase 5**: Concurrency features add NEW opcodes and codegen paths but don't change how EXISTING code compiles. The compiler itself is single-threaded (no spawn/channel in jda1.jda), so self-host convergence should be straightforward — the new code is dead during self-compilation.

**Exception**: If we add `atomic_load`/`atomic_store` as general builtins, the compiler might use them internally in a future phase. For now, they only appear in user programs.

---

## Test Strategy

Each milestone adds tests. Target: 110+ tests by end of Phase 6.

| Milestone | Test Categories | Count |
|-----------|----------------|-------|
| M1 | Atomic load/store, CAS, fetch-add, RDTSC | 5 |
| M2 | Inline asm register binding, memory ops, labels | 4 |
| M3 | Spawn basic, spawn many, spawn with args | 3 |
| M4 | Round-robin, yield order, nested spawn, thread exit | 4 |
| M5 | Send/recv, buffered, close, ownership, producer-consumer | 5 |
| M6 | Parallel spawn, work-stealing, cross-thread channel | 3 |
| M7 | epoll TCP echo, concurrent connections | 3 |
| M8 | Deadlock simple, channel cycle | 2 |
| **Total** | | **29 new tests** |

---

## Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Context switch corrupts registers | Critical | M2 tests verify every callee-saved register round-trips correctly |
| clone() stack setup wrong | Critical | Test with trivial child (just exit(0)) before scheduler loop |
| Work-stealing ABA problem | High | Use 64-bit head/tail counters — won't wrap in practice |
| Inline asm misencodes x86 | High | Compare emitted bytes against nasm output for same instructions |
| Deadlock in scheduler itself | High | Single-threaded scheduler (M4) validates all logic before M:N (M6) |
| epoll missed events | Medium | Use level-triggered mode (not edge-triggered) |
| Channel generic monomorphization bugs | Medium | Test with i64, *i8, and struct types |
| Binary size explosion from new opcodes | Low | New opcodes are small fixed sequences (~10 bytes each) |

---

## Definition of Done

Phase 6 is complete when:

1. This program compiles and runs correctly:
```jda
fn fib(n: i64, ch: &Channel<i64>) {
    if n <= 1 { chan_send(ch, n)   ret }
    let c1 = chan_new<i64>(1)
    let c2 = chan_new<i64>(1)
    spawn fib(n - 1, &c1)
    spawn fib(n - 2, &c2)
    let a = chan_recv(&c1)?
    let b = chan_recv(&c2)?
    chan_send(ch, a + b)
}

fn main() {
    let ch = chan_new<i64>(1)
    spawn fib(20, &ch)
    let result = chan_recv(&ch)?
    print_int(result)   ; 6765
}
```

2. Spawning 10,000 J-Threads completes without OOM (each uses 64KB stack = 640MB total)
3. TCP echo server handles 100 concurrent connections via green threads
4. Deadlock is detected and reported for `chan_recv` on a closed empty channel with no senders
5. All conformance tests pass (110+)
6. Self-host converged
