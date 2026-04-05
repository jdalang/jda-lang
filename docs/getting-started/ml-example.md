# Train a Neural Network

Train a multilayer perceptron (MLP) from scratch — no frameworks, no dependencies. Jda compiles to native x86-64, so you get C-level speed with simple syntax.

## Prerequisites

[Install Jda](../../README.md#installation), then verify: `jda --version`

## 1. What we're building

A 2→8→1 neural network that learns XOR:

| Input A | Input B | Expected Output |
|---------|---------|-----------------|
| 0 | 0 | 0 |
| 0 | 1 | 1 |
| 1 | 0 | 1 |
| 1 | 1 | 0 |

XOR is the classic "non-linearly separable" problem — it requires a hidden layer to solve.

## 2. Write the code

Create `xor.jda`:

```jda
; XOR neural network — trains a 2→8→1 MLP from scratch
; Uses f64 floats, for-range loops, and compound assignment

; --- Pseudo-random number generator (LCG) ---
let g_seed = 42

fn rand_next() -> i64 {
    g_seed = g_seed * 6364136223846793005 + 1442695040888963407
    ret g_seed
}

; Random float in [-0.5, 0.5] (as f64)
fn rand_weight() -> f64 {
    let r = rand_next()
    if r < 0 { r = 0 - r }
    let rem = r % 10000
    let f = int_to_f64(rem)
    let scale = 10000.0
    let result = f / scale
    let half = 0.5
    ret result - half
}

; --- Activation: ReLU ---
fn relu(x: f64) -> f64 {
    if f64_to_int(x) < 0 { ret 0.0 }
    ret x
}

fn relu_deriv(x: f64) -> f64 {
    if f64_to_int(x) <= 0 { ret 0.0 }
    ret 1.0
}

; --- Network parameters ---
; Layer 1: 2 inputs → 8 hidden neurons (16 weights + 8 biases)
; Layer 2: 8 hidden → 1 output (8 weights + 1 bias)

fn main() -> i64 {
    ; Allocate weight arrays
    let w1: &f64 = alloc_pages(1)   ; 2×8 = 16 weights
    let b1: &f64 = alloc_pages(1)   ; 8 biases
    let w2: &f64 = alloc_pages(1)   ; 8 weights
    let b2: &f64 = alloc_pages(1)   ; 1 bias

    ; Initialize with random weights
    for i in range(16) { w1[i] = rand_weight() }
    for i in range(8)  { b1[i] = 0.0 }
    for i in range(8)  { w2[i] = rand_weight() }
    b2[0] = 0.0

    ; Training data: XOR truth table
    let inputs: &f64 = alloc_pages(1)   ; 4 samples × 2 inputs = 8
    let targets: &f64 = alloc_pages(1)  ; 4 targets

    ; [0,0]→0  [0,1]→1  [1,0]→1  [1,1]→0
    inputs[0] = 0.0  inputs[1] = 0.0  targets[0] = 0.0
    inputs[2] = 0.0  inputs[3] = 1.0  targets[1] = 1.0
    inputs[4] = 1.0  inputs[5] = 0.0  targets[2] = 1.0
    inputs[6] = 1.0  inputs[7] = 1.0  targets[3] = 0.0

    ; Intermediate buffers
    let hidden: &f64 = alloc_pages(1)    ; 8 hidden activations
    let pre_relu: &f64 = alloc_pages(1)  ; 8 pre-activation values
    let grad_h: &f64 = alloc_pages(1)    ; 8 hidden gradients

    let lr = 0.01
    let epochs = 5000

    ; --- Training loop ---
    for epoch in range(epochs) {
        let total_loss = 0.0

        for sample in range(4) {
            ; Get input pair
            let base = sample * 2
            let x0 = inputs[base]
            let x1_val = inputs[base + 1]
            let target = targets[sample]

            ; Forward: hidden layer
            for j in range(8) {
                let widx = j * 2
                let sum = w1[widx] * x0 + w1[widx + 1] * x1_val + b1[j]
                pre_relu[j] = sum
                hidden[j] = relu(sum)
            }

            ; Forward: output layer
            let output = b2[0]
            for j in range(8) {
                output = output + w2[j] * hidden[j]
            }

            ; MSE loss
            let diff = output - target
            let loss = diff * diff
            total_loss = total_loss + loss

            ; Backward: output layer gradient
            let grad_out = 2.0 * diff

            ; Backward: hidden layer gradients
            for j in range(8) {
                grad_h[j] = grad_out * w2[j] * relu_deriv(pre_relu[j])
            }

            ; Update output weights
            for j in range(8) {
                w2[j] = w2[j] - lr * grad_out * hidden[j]
            }
            b2[0] = b2[0] - lr * grad_out

            ; Update hidden weights
            for j in range(8) {
                let widx = j * 2
                w1[widx] = w1[widx] - lr * grad_h[j] * x0
                w1[widx + 1] = w1[widx + 1] - lr * grad_h[j] * x1_val
                b1[j] = b1[j] - lr * grad_h[j]
            }
        }

        ; Print loss every 1000 epochs
        if epoch % 1000 == 0 {
            let loss_int = f64_to_int(total_loss * 10000.0)
            print("epoch {epoch} loss×10000={loss_int}\n")
        }
    }

    ; --- Test ---
    print("\n--- XOR Results ---\n")
    let correct = 0

    for sample in range(4) {
        let base = sample * 2
        let x0 = inputs[base]
        let x1_val = inputs[base + 1]
        let target = targets[sample]

        ; Forward pass
        for j in range(8) {
            let widx = j * 2
            let sum = w1[widx] * x0 + w1[widx + 1] * x1_val + b1[j]
            hidden[j] = relu(sum)
        }
        let output = b2[0]
        for j in range(8) {
            output = output + w2[j] * hidden[j]
        }

        ; Round to 0 or 1
        let pred = 0
        if f64_to_int(output * 100.0) > 50 { pred = 1 }
        let tgt = f64_to_int(target)

        let x0i = f64_to_int(x0)
        let x1i = f64_to_int(x1_val)
        print("{x0i} XOR {x1i} = {pred}")
        if pred == tgt {
            print(" ✓\n")
            correct += 1
        } else {
            print(" ✗\n")
        }
    }

    print("{correct}/4 correct\n")
    if correct == 4 { print("PASS\n") }
    ret 0
}
```

## 3. Build and run

```bash
jda build xor.jda -o xor
./xor
```

Expected output:

```
epoch 0 loss×10000=22814
epoch 1000 loss×10000=285
epoch 2000 loss×10000=12
epoch 3000 loss×10000=3
epoch 4000 loss×10000=1

--- XOR Results ---
0 XOR 0 = 0 ✓
0 XOR 1 = 1 ✓
1 XOR 0 = 1 ✓
1 XOR 1 = 0 ✓
4/4 correct
PASS
```

## How it works

### Network architecture

```
Input (2) → Hidden (8, ReLU) → Output (1, linear)
```

- **Forward pass**: multiply inputs by weights, add bias, apply ReLU activation
- **Loss**: mean squared error (MSE) = (predicted - target)²
- **Backward pass**: compute gradients via chain rule, update weights with SGD
- **Learning rate**: 0.01, trained for 5,000 epochs

### Why it's fast

Jda compiles directly to x86-64 machine code. There's no interpreter, no VM, no GC. The training loop is tight native code — `f64` operations map to SSE2 instructions.

| Task | Jda | Python (no NumPy) | Speedup |
|------|-----|-------------------|---------|
| XOR training (5K epochs) | 21 ms | 778 ms | **~37x** |

See [apps/jda-ml-demo](../../apps/) for the full benchmark with sine approximation and matrix multiply.

### Key Jda features used

| Feature | Example | What it does |
|---------|---------|--------------|
| `f64` floats | `let lr = 0.01` | Native float literals |
| `for` range | `for i in range(8)` | Iterate 0..n |
| `+=` | `total_loss = total_loss + loss` | Compound assignment |
| `%` modulo | `epoch % 1000 == 0` | Print every N epochs |
| `&f64` arrays | `let w1: &f64 = alloc_pages(1)` | Heap-allocated float arrays |
| `f64_to_int` | `f64_to_int(output * 100.0)` | Float → int conversion |
| `int_to_f64` | `int_to_f64(rem)` | Int → float conversion |

## 4. Using the stdlib neural network library

For larger networks, Jda's `nn.jda` stdlib provides tensor-based operations:

```jda
; Using stdlib nn.jda
let x = tensor_new(batch, 2)       ; input tensor
let w1 = tensor_new(2, 8)          ; weight matrix
let out = tensor_new(batch, 8)     ; output buffer

linear_forward(x, w1, bias1, out)  ; matrix multiply + bias
relu_forward(out, activated)       ; activation
let loss = mse_loss(pred, target)  ; compute loss
mse_backward(pred, target, grad)   ; backprop
sgd_step(w1, grad_w1, lr)          ; update weights
```

## Next steps

- [Build a CLI Tool](cli-tool.md) — parse args, process files
- [Build an HTTP Server](http-server.md) — serve web requests
- See [apps/jda-ml-demo](../../apps/) for the full ML benchmark suite
