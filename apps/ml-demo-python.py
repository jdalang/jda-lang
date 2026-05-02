#!/usr/bin/env python3
"""
ML Demo — Neural Network Training from Scratch in Pure Python
=============================================================
Equivalent of apps/jda-ml-demo.jda for head-to-head comparison.

NO NumPy, NO PyTorch — pure Python math only (fair comparison).
Both implementations do the same operations loop-by-loop.

Usage:
    python3 apps/ml-demo-python.py
"""

import math
import time
import random

# ---------------------------------------------------------------------------
# Tensor (flat list of floats, with shape metadata)
# ---------------------------------------------------------------------------

class Tensor:
    __slots__ = ('data', 'shape')
    def __init__(self, shape):
        self.shape = tuple(shape)
        self.data = [0.0] * math.prod(shape)
    def __len__(self):
        return len(self.data)

def tensor_new1(n):
    return Tensor([n])

def tensor_new2(r, c):
    return Tensor([r, c])

def tensor_get(t, i):
    return t.data[i]

def tensor_set(t, i, v):
    t.data[i] = v

def tensor_shape(t, dim):
    return t.shape[dim]

def tensor_len(t):
    return len(t.data)

def tensor_fill(t, v):
    for i in range(len(t.data)):
        t.data[i] = v

# ---------------------------------------------------------------------------
# Neural network primitives (identical logic to Jda version)
# ---------------------------------------------------------------------------

def linear_forward(x, w, bias, out):
    batch = tensor_shape(x, 0)
    in_f  = tensor_shape(x, 1)
    out_f = tensor_shape(w, 0)
    for i in range(batch):
        for j in range(out_f):
            acc = tensor_get(bias, j)
            for k in range(in_f):
                acc += tensor_get(x, i*in_f+k) * tensor_get(w, j*in_f+k)
            tensor_set(out, i*out_f+j, acc)

def relu_forward(a, out):
    for i in range(tensor_len(a)):
        v = tensor_get(a, i)
        tensor_set(out, i, max(0.0, v))

def relu_backward(pre_relu, grad_out, grad_in):
    for i in range(tensor_len(pre_relu)):
        tensor_set(grad_in, i, tensor_get(grad_out, i) if tensor_get(pre_relu, i) > 0 else 0.0)

def backward_weights(x, w, grad_out, grad_w):
    batch = tensor_shape(x, 0)
    in_f  = tensor_shape(x, 1)
    out_f = tensor_shape(w, 0)
    for j in range(out_f):
        for k in range(in_f):
            acc = 0.0
            for i in range(batch):
                acc += tensor_get(grad_out, i*out_f+j) * tensor_get(x, i*in_f+k)
            idx = j*in_f+k
            tensor_set(grad_w, idx, tensor_get(grad_w, idx) + acc)

def backward_bias(grad_out, grad_b, batch, out_f):
    for j in range(out_f):
        acc = 0.0
        for i in range(batch):
            acc += tensor_get(grad_out, i*out_f+j)
        tensor_set(grad_b, j, tensor_get(grad_b, j) + acc)

def backward_input(w, grad_out, grad_in):
    batch = tensor_shape(grad_in, 0)
    in_f  = tensor_shape(grad_in, 1)
    out_f = tensor_shape(w, 0)
    for i in range(batch):
        for k in range(in_f):
            acc = 0.0
            for j in range(out_f):
                acc += tensor_get(grad_out, i*out_f+j) * tensor_get(w, j*in_f+k)
            idx = i*in_f+k
            tensor_set(grad_in, idx, tensor_get(grad_in, idx) + acc)

def mse_loss(pred, target):
    n = tensor_len(pred)
    s = 0.0
    for i in range(n):
        d = tensor_get(pred, i) - tensor_get(target, i)
        s += d * d
    return s / n

def mse_backward(pred, target, grad_out):
    n = tensor_len(pred)
    scale = 2.0 / n
    for i in range(n):
        d = tensor_get(pred, i) - tensor_get(target, i)
        tensor_set(grad_out, i, scale * d)

def sgd_step(params, grads, lr):
    for i in range(tensor_len(params)):
        tensor_set(params, i, tensor_get(params, i) - lr * tensor_get(grads, i))
        tensor_set(grads, i, 0.0)

def zero_t(t):
    tensor_fill(t, 0.0)

def init_weights_uniform(t, rng, scale):
    half = scale / 2
    for i in range(tensor_len(t)):
        tensor_set(t, i, rng.random() * scale - half)

def print_f64(v):
    return f"{v:.4f}"

# ---------------------------------------------------------------------------
# Matmul benchmark
# ---------------------------------------------------------------------------

def matmul_bench(a, b, c, M, K, N):
    for i in range(M):
        for j in range(N):
            acc = 0.0
            for k in range(K):
                acc += tensor_get(a, i*K+k) * tensor_get(b, k*N+j)
            tensor_set(c, i*N+j, acc)

# ---------------------------------------------------------------------------
# Task 1: XOR Classification
# ---------------------------------------------------------------------------

def task_xor():
    print("=== Task 1: XOR Classification ===")
    print("Architecture: 2 -> 8 -> 1 MLP")
    print("Dataset: 4 XOR samples")
    print("Epochs: 5000, LR: 0.1\n")

    batch, hidden = 4, 8
    x = tensor_new2(4, 2)
    for i, v in enumerate([0,0, 0,1, 1,0, 1,1]):
        tensor_set(x, i, float(v))

    y = tensor_new2(4, 1)
    for i, v in enumerate([0, 1, 1, 0]):
        tensor_set(y, i, float(v))

    rng = random.Random(42)
    w1  = tensor_new2(hidden, 2);  init_weights_uniform(w1, rng, 2.0)
    b1  = tensor_new1(hidden);     tensor_fill(b1, 0.0)
    gw1 = tensor_new2(hidden, 2);  gb1 = tensor_new1(hidden)
    w2  = tensor_new2(1, hidden);  init_weights_uniform(w2, rng, 2.0)
    b2  = tensor_new1(1);          tensor_fill(b2, 0.0)
    gw2 = tensor_new2(1, hidden);  gb2 = tensor_new1(1)

    h1  = tensor_new2(4, hidden)
    h1r = tensor_new2(4, hidden)
    out = tensor_new2(4, 1)
    g_out = tensor_new2(4, 1)
    g_h1r = tensor_new2(4, hidden)
    g_h1  = tensor_new2(4, hidden)
    g_x   = tensor_new2(4, 2)

    lr = 0.1
    t0 = time.monotonic()

    for epoch in range(5000):
        linear_forward(x, w1, b1, h1)
        relu_forward(h1, h1r)
        linear_forward(h1r, w2, b2, out)

        if epoch % 1000 == 0:
            loss = mse_loss(out, y)
            print(f"  epoch {epoch}  loss={print_f64(loss)}")

        mse_backward(out, y, g_out)
        zero_t(gw2); zero_t(gb2); zero_t(g_h1r)
        backward_weights(h1r, w2, g_out, gw2)
        backward_bias(g_out, gb2, batch, 1)
        backward_input(w2, g_out, g_h1r)
        relu_backward(h1, g_h1r, g_h1)
        zero_t(gw1); zero_t(gb1); zero_t(g_x)
        backward_weights(x, w1, g_h1, gw1)
        backward_bias(g_h1, gb1, batch, hidden)
        backward_input(w1, g_h1, g_x)

        sgd_step(w1, gw1, lr)
        sgd_step(b1, gb1, lr)
        sgd_step(w2, gw2, lr)
        sgd_step(b2, gb2, lr)

    elapsed = int((time.monotonic() - t0) * 1000)

    linear_forward(x, w1, b1, h1)
    relu_forward(h1, h1r)
    linear_forward(h1r, w2, b2, out)

    print("\nPredictions:")
    labels = ["[0,0]", "[0,1]", "[1,0]", "[1,1]"]
    expected = [0, 1, 1, 0]
    correct = 0
    for i in range(4):
        p = tensor_get(out, i)
        print(f"  {labels[i]} -> {print_f64(p)}  (expected ~{expected[i]})")
        if (expected[i] == 0 and p < 0.5) or (expected[i] == 1 and p > 0.5):
            correct += 1

    result = "PASS" if correct == 4 else "FAIL"
    print(f"  Result: {result} ({correct}/4 correct)")
    print(f"  Final loss: {print_f64(mse_loss(out, y))}")
    print(f"  Time: {elapsed} ms\n")

# ---------------------------------------------------------------------------
# Task 2: Sine Approximation
# ---------------------------------------------------------------------------

def task_sine():
    print("=== Task 2: Sine Approximation ===")
    print("Architecture: 1 -> 16 -> 1 MLP")
    print("Dataset: 32 samples of sin(x), x in [0, 6.28]")
    print("Epochs: 10000, LR: 0.01\n")

    n_samples, hidden = 32, 16

    x = tensor_new2(n_samples, 1)
    y = tensor_new2(n_samples, 1)
    step = 2 * math.pi / n_samples
    for i in range(n_samples):
        xv = i * step
        tensor_set(x, i, xv)
        tensor_set(y, i, math.sin(xv))

    rng = random.Random(12345)
    w1  = tensor_new2(hidden, 1);  init_weights_uniform(w1, rng, 2.0)
    b1  = tensor_new1(hidden);     tensor_fill(b1, 0.0)
    gw1 = tensor_new2(hidden, 1);  gb1 = tensor_new1(hidden)
    w2  = tensor_new2(1, hidden);  init_weights_uniform(w2, rng, 2.0)
    b2  = tensor_new1(1);          tensor_fill(b2, 0.0)
    gw2 = tensor_new2(1, hidden);  gb2 = tensor_new1(1)

    h1  = tensor_new2(n_samples, hidden)
    h1r = tensor_new2(n_samples, hidden)
    out = tensor_new2(n_samples, 1)
    g_out = tensor_new2(n_samples, 1)
    g_h1r = tensor_new2(n_samples, hidden)
    g_h1  = tensor_new2(n_samples, hidden)
    g_x   = tensor_new2(n_samples, 1)

    lr = 0.01
    t0 = time.monotonic()

    for epoch in range(10000):
        linear_forward(x, w1, b1, h1)
        relu_forward(h1, h1r)
        linear_forward(h1r, w2, b2, out)

        if epoch % 2000 == 0:
            loss = mse_loss(out, y)
            print(f"  epoch {epoch}  loss={print_f64(loss)}")

        mse_backward(out, y, g_out)
        zero_t(gw2); zero_t(gb2); zero_t(g_h1r)
        backward_weights(h1r, w2, g_out, gw2)
        backward_bias(g_out, gb2, n_samples, 1)
        backward_input(w2, g_out, g_h1r)
        relu_backward(h1, g_h1r, g_h1)
        zero_t(gw1); zero_t(gb1); zero_t(g_x)
        backward_weights(x, w1, g_h1, gw1)
        backward_bias(g_h1, gb1, n_samples, hidden)
        backward_input(w1, g_h1, g_x)

        sgd_step(w1, gw1, lr)
        sgd_step(b1, gb1, lr)
        sgd_step(w2, gw2, lr)
        sgd_step(b2, gb2, lr)

    elapsed = int((time.monotonic() - t0) * 1000)

    linear_forward(x, w1, b1, h1)
    relu_forward(h1, h1r)
    linear_forward(h1r, w2, b2, out)

    print("\nSample predictions (x -> predicted vs actual):")
    for pi in range(8):
        idx = pi * 4
        xv = tensor_get(x, idx)
        pv = tensor_get(out, idx)
        av = tensor_get(y, idx)
        print(f"  x={print_f64(xv)}  pred={print_f64(pv)}  actual={print_f64(av)}")

    print(f"  Final loss: {print_f64(mse_loss(out, y))}")
    print(f"  Time: {elapsed} ms\n")

# ---------------------------------------------------------------------------
# Task 3: Matrix Multiply Benchmark
# ---------------------------------------------------------------------------

def task_matmul():
    print("=== Task 3: Matrix Multiply Benchmark ===")
    print("Size: 64x64 @ 64x64 (10 iterations)\n")

    M = K = N = 64
    rng = random.Random(999)
    a = tensor_new2(M, K)
    b = tensor_new2(K, N)
    c = tensor_new2(M, N)
    init_weights_uniform(a, rng, 1.0)
    init_weights_uniform(b, rng, 1.0)

    # Warm up
    matmul_bench(a, b, c, M, K, N)

    t0 = time.monotonic()
    for _ in range(10):
        matmul_bench(a, b, c, M, K, N)
    elapsed = int((time.monotonic() - t0) * 1000)
    avg = elapsed // 10

    s = sum(abs(tensor_get(c, i)) for i in range(16))
    print(f"  Total (10 iters): {elapsed} ms")
    print(f"  Average: {avg} ms per matmul")
    print(f"  Verification: {'PASS' if s > 0 else 'FAIL'}")
    print(f"  FLOP/matmul: 524288\n")

# ---------------------------------------------------------------------------

if __name__ == "__main__":
    print("=" * 64)
    print("  Python ML Demo — Neural Network Training from Scratch")
    print("  Runtime: CPython (pure Python, NO NumPy)")
    print("  Interpreted, dynamic dispatch, GC overhead")
    print("=" * 64)
    print()

    task_xor()
    task_sine()
    task_matmul()

    print("=" * 64)
    print("  All tasks complete. Compare with:")
    print("    ./apps/jda-ml-demo  (compiled Jda)")
    print("=" * 64)
