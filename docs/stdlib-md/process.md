# process

; jda::process — Process management

## Constants

```jda
SYS_READ      =  0
```

```jda
SYS_WRITE     =  1
```

```jda
SYS_OPEN      =  2
```

```jda
SYS_CLOSE     =  3
```

```jda
SYS_STAT      =  4
```

```jda
SYS_MMAP      =  9
```

```jda
SYS_RT_SIGACTION   = 13
```

```jda
SYS_RT_SIGPROCMASK = 14
```

```jda
SYS_RT_SIGRETURN   = 15
```

```jda
SYS_IOCTL     = 16
```

```jda
SYS_PIPE      = 22
```

```jda
SYS_DUP       = 32
```

```jda
SYS_DUP2      = 33
```

```jda
SYS_GETPID    = 39
```

```jda
SYS_CLONE     = 56
```

```jda
SYS_FORK      = 57
```

```jda
SYS_VFORK     = 58
```

```jda
SYS_EXECVE    = 59
```

```jda
SYS_EXIT      = 60
```

```jda
SYS_WAIT4     = 61
```

```jda
SYS_KILL      = 62
```

```jda
SYS_GETPPID   = 110
```

```jda
SYS_GETUID    = 102
```

```jda
SYS_GETGID    = 104
```

```jda
SYS_GETEUID   = 107
```

```jda
SYS_GETEGID   = 108
```

```jda
SYS_SIGALTSTACK= 131
```

```jda
SYS_PRCTL     = 157
```

```jda
SYS_SETPGID   = 109
```

```jda
SYS_GETPGID   = 121
```

```jda
SYS_SETSID    = 112
```

```jda
SYS_ENVIRON   = -1   ; accessed via auxv, not a syscall
```

```jda
SIGHUP    =  1    ; hangup
```

```jda
SIGINT    =  2    ; interrupt (Ctrl-C)
```

```jda
SIGQUIT   =  3    ; quit
```

```jda
SIGILL    =  4    ; illegal instruction
```

```jda
SIGTRAP   =  5    ; trace / breakpoint
```

```jda
SIGABRT   =  6    ; abort
```

```jda
SIGBUS    =  7    ; bus error
```

```jda
SIGFPE    =  8    ; floating-point exception
```

```jda
SIGKILL   =  9    ; kill (cannot be caught)
```

```jda
SIGUSR1   = 10    ; user-defined 1
```

```jda
SIGSEGV   = 11    ; segfault
```

```jda
SIGUSR2   = 12    ; user-defined 2
```

```jda
SIGPIPE   = 13    ; broken pipe
```

```jda
SIGALRM   = 14    ; alarm clock
```

```jda
SIGTERM   = 15    ; termination
```

```jda
SIGCHLD   = 17    ; child stopped or exited
```

```jda
SIGCONT   = 18    ; continue
```

```jda
SIGSTOP   = 19    ; stop (cannot be caught)
```

```jda
SIGTSTP   = 20    ; terminal stop (Ctrl-Z)
```

```jda
SIGTTIN   = 21    ; background read from tty
```

```jda
SIGTTOU   = 22    ; background write to tty
```

```jda
SIGURG    = 23    ; urgent data on socket
```

```jda
SIGWINCH  = 28    ; terminal resize
```

```jda
SIG_DFL   = 0     ; default action
```

```jda
SIG_IGN   = 1     ; ignore signal
```

```jda
WNOHANG   = 1     ; non-blocking waitpid
```

```jda
PR_SET_NAME   = 15
```

```jda
PR_GET_NAME   = 16
```

```jda
PR_SET_DUMPABLE = 4
```

```jda
PR_GET_DUMPABLE = 3
```

```jda
PR_SET_PDEATHSIG = 1   ; signal sent to child when parent dies
```

## Structs

### `SigAction`

```jda
struct SigAction {
    handler:  i64      ; fn pointer or SIG_DFL / SIG_IGN
    flags:    i64      ; SA_* flags
    restorer: i64      ; signal trampoline (kernel sets this)
    mask:     u64[2]   ; signal mask (128 bits)
}
```

### `ProcInfo`

```jda
struct ProcInfo {
    pid:      i32
    ppid:     i32
    uid:      i32
    gid:      i32
    euid:     i32
    egid:     i32
    pgid:     i32
    sid:      i32
}
```

### `SpawnOpts`

```jda
struct SpawnOpts {
    stdin_fd:  i32   ; -1 = inherit
    stdout_fd: i32   ; -1 = inherit
    stderr_fd: i32   ; -1 = inherit
    cwd:       &i8   ; null = inherit
    env:       &&i8  ; null = inherit current environ
    detach:    i32   ; 1 = new session (setsid)
}
```

### `ChildProc`

```jda
struct ChildProc {
    pid:    i32
    stdin:  i32   ; write end of stdin pipe  (-1 if not piped)
    stdout: i32   ; read  end of stdout pipe (-1 if not piped)
    stderr: i32   ; read  end of stderr pipe (-1 if not piped)
}
```

### `WaitResult`

```jda
struct WaitResult {
    pid:    i32
    status: i32
    exited: i32
    code:   i32     ; exit code if exited
    signal: i32     ; signal if killed by signal
}
```

### `Pipe`

```jda
struct Pipe {
    read_fd:  i32
    write_fd: i32
}
```

## Functions

| Function | Description |
|----------|-------------|
| `wifexited` |  |
| `wexitstatus` |  |
| `wifsignaled` |  |
| `wtermsig` |  |
| `wifstopped` |  |
| `wstopsig` |  |
| `getpid` |  |
| `getppid` |  |
| `getuid` |  |
| `getgid` |  |
| `exit` |  |
| `abort` |  |
| `fork` |  |
| `execve` |  |
| `exec_argv` |  |
| `waitpid` |  |
| `wait_any` |  |
| `run` |  |
| `pipe2` |  |
| `dup2` |  |
| `close_fd` |  |
| `spawn` |  |
| `spawn_output` |  |
| `kill` |  |
| `killpg` |  |
| `raise_sig` |  |
| `signal` |  |
| `signal_ignore` |  |
| `signal_default` |  |
| `signal_block` |  |
| `signal_unblock` |  |
| `environ` |  |
| `process_init` |  |
| `getenv` |  |
| `setenv` |  |
| `unsetenv` |  |
| `proc_info` |  |
| `pipe_open` |  |
| `pipe_write` |  |
| `pipe_read` |  |
| `pipe_close_write` |  |
| `pipe_close_read` |  |
| `daemonize` |  |
| `set_process_name` |  |
| `get_process_name` |  |
| `set_pdeathsig` |  |
| `disable_coredump` |  |

### Details

#### `wifexited`

```jda
fn wifexited(status: i32) -> i32  
```

#### `wexitstatus`

```jda
fn wexitstatus(status: i32) -> i32
```

#### `wifsignaled`

```jda
fn wifsignaled(status: i32) -> i32
```

#### `wtermsig`

```jda
fn wtermsig(status: i32) -> i32   
```

#### `wifstopped`

```jda
fn wifstopped(status: i32) -> i32 
```

#### `wstopsig`

```jda
fn wstopsig(status: i32) -> i32   
```

#### `getpid`

```jda
fn getpid() -> i32
```

#### `getppid`

```jda
fn getppid() -> i32
```

#### `getuid`

```jda
fn getuid() -> i32
```

#### `getgid`

```jda
fn getgid() -> i32
```

#### `exit`

```jda
fn exit(code: i32)
```

#### `abort`

```jda
fn abort()
```

#### `fork`

```jda
fn fork() -> i32
```

#### `execve`

```jda
fn execve(path: &i8, argv: &&i8, envp: &&i8) -> i32
```

#### `exec_argv`

```jda
fn exec_argv(path: &i8, argv: &&i8) -> i32
```

#### `waitpid`

```jda
fn waitpid(pid: i32, status: &i32, options: i32) -> i32
```

#### `wait_any`

```jda
fn wait_any(opts: i32) -> WaitResult
```

#### `run`

```jda
fn run(path: &i8, argv: &&i8) -> i32
```

#### `pipe2`

```jda
fn pipe2(fds: &i32) -> i32
```

#### `dup2`

```jda
fn dup2(old_fd: i32, new_fd: i32) -> i32
```

#### `close_fd`

```jda
fn close_fd(fd: i32)
```

#### `spawn`

```jda
fn spawn(path: &i8, argv: &&i8, opts: &SpawnOpts) -> ChildProc
```

#### `spawn_output`

```jda
fn spawn_output(path: &i8, argv: &&i8, out: &i8, cap: i64) -> i64
```

#### `kill`

```jda
fn kill(pid: i32, sig: i32) -> i32
```

#### `killpg`

```jda
fn killpg(pgid: i32, sig: i32) -> i32
```

#### `raise_sig`

```jda
fn raise_sig(sig: i32)
```

#### `signal`

```jda
fn signal(sig: i32, handler: i64) -> i32
```

#### `signal_ignore`

```jda
fn signal_ignore(sig: i32)
```

#### `signal_default`

```jda
fn signal_default(sig: i32)
```

#### `signal_block`

```jda
fn signal_block(sig: i32)
```

#### `signal_unblock`

```jda
fn signal_unblock(sig: i32)
```

#### `environ`

```jda
fn environ() -> &&i8
```

#### `process_init`

```jda
fn process_init(argc: i64, argv: &&i8)
```

#### `getenv`

```jda
fn getenv(name: &i8) -> &i8
```

#### `setenv`

```jda
fn setenv(name: &i8, value: &i8, overwrite: i32) -> i32
```

#### `unsetenv`

```jda
fn unsetenv(name: &i8) -> i32
```

#### `proc_info`

```jda
fn proc_info() -> ProcInfo
```

#### `pipe_open`

```jda
fn pipe_open() -> Pipe
```

#### `pipe_write`

```jda
fn pipe_write(p: &Pipe, data: &i8, len: i64) -> i64
```

#### `pipe_read`

```jda
fn pipe_read(p: &Pipe, buf: &i8, cap: i64) -> i64
```

#### `pipe_close_write`

```jda
fn pipe_close_write(p: &Pipe)
```

#### `pipe_close_read`

```jda
fn pipe_close_read(p: &Pipe) 
```

#### `daemonize`

```jda
fn daemonize() -> i32
```

#### `set_process_name`

```jda
fn set_process_name(name: &i8)
```

#### `get_process_name`

```jda
fn get_process_name(out: &i8)
```

#### `set_pdeathsig`

```jda
fn set_pdeathsig(sig: i32)
```

#### `disable_coredump`

```jda
fn disable_coredump()
```

---

*Generated by `jda-doc-md`*
