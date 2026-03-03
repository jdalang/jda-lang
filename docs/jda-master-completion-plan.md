# JDA -- Master Completion Plan

## Overview

This document defines the complete staged execution roadmap for Jda.
Nothing from the original roadmap is removed --- this plan only
sequences execution logically for long-term success.

------------------------------------------------------------------------

# STAGE 1 --- Self-Hosting Lock (0--3 Months)

## Objective

jda1 compiles jda1.jda → identical output binary. Delete jda0
dependency.

## Required Features

-   Multi-function support
-   Struct definitions + layout
-   Array declarations + indexing
-   Pointer/reference support
-   const declarations
-   Logical operators (and/or/\>=/\<=)
-   else-if chains
-   String escape sequences
-   print(int)
-   5+ argument calls
-   Roundtrip verification

## Deliverable

jda1 → jda1-gen2 → identical output

------------------------------------------------------------------------

# STAGE 2 --- Minimal Release (3--5 Months)

## Objective

Make Jda usable by external developers.

## Add

-   CLI (`jda build`, `jda run`)
-   Linux installer script
-   Proper error diagnostics
-   Line/column reporting
-   Minimal stdlib (fs, time, fmt)
-   Versioning

## Deliverable

One-command install and build workflow.

------------------------------------------------------------------------

# STAGE 3 --- Language Core Maturity (5--12 Months)

## Implement

-   Full type checking
-   Type inference
-   Struct field validation
-   Enums
-   Pattern matching
-   Result\<T,E\>
-   `?` operator
-   impl blocks and methods
-   Minimal generics (monomorphization)
-   Basic ownership model (single-owner rule)

## Deliverable

Ability to build real-world CLI tools and servers.

------------------------------------------------------------------------

# STAGE 4 --- Performance Validation (12--16 Months)

## Add

-   Graph-coloring register allocator
-   Function inlining
-   Tail-call optimization
-   Loop unrolling
-   Benchmark suite

## Publish Benchmarks

Compare Jda vs C vs Go vs Rust.

------------------------------------------------------------------------

# STAGE 5 --- Concurrency Runtime (Optional Path A)

-   J-Threads
-   Lock-free channels
-   Work-stealing scheduler
-   spawn keyword
-   Deadlock detection

------------------------------------------------------------------------

# STAGE 6 --- ML Runtime (Optional Path B)

-   Tensor primitives
-   Compile-time shape checking
-   Autograd
-   SIMD vectorization
-   GPU backend
-   ML standard library
-   Transformer demo

------------------------------------------------------------------------

# STAGE 7 --- Ecosystem & Tooling

-   Package manager
-   LSP
-   Formatter
-   Test framework
-   Documentation site
-   Examples
-   Playground (WASM)
-   macOS backend
-   Windows backend

------------------------------------------------------------------------

# Realistic Timeline (Solo Developer)

Month 3 → Self-host achieved\
Month 5 → Usable 0.1 release\
Month 12 → Strong language core\
Month 16 → Performance credibility\
Year 2 → Concurrency OR ML identity\
Year 3 → Ecosystem maturity

------------------------------------------------------------------------

# Final Completion Criteria

Jda is considered mature when:

-   Self-hosted
-   Strong type system
-   Installable CLI
-   Public benchmarks available
-   Used in multiple real projects
-   Stable release process
