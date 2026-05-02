#!/bin/bash
# Stage 0 to Stage 1 incremental compilation workflow
# Strategy: Use Python tools to extract and validate Stage 0 can compile progressively more jda1 features
# 
# Usage:
#   ./compile_workflow.sh <source.jda> <output_binary> [--analyze] [--split] [--validate]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"

SOURCE_FILE="${1:-}"
OUTPUT_BINARY="${2:-}"
ANALYZE="${3:-}"

if [[ -z "$SOURCE_FILE" || -z "$OUTPUT_BINARY" ]]; then
    echo "Stage 0 → Stage 1 Incremental Compilation Workflow"
    echo ""
    echo "Usage: $0 <source.jda> <output_binary> [--analyze|--split|--validate]"
    echo ""
    echo "Examples:"
    echo "  $0 bootstrap/stage1/jda1.jda jda1_out --analyze"
    echo "  $0 bootstrap/stage1/jda1.jda jda1_out --split"
    echo "  $0 examples/hello.jda hello_out"
    echo ""
    exit 1
fi

# Verify source file exists
if [[ ! -f "$SOURCE_FILE" ]]; then
    echo "❌ Error: Source file not found: $SOURCE_FILE"
    exit 1
fi

echo "╔════════════════════════════════════════════════════════════════════╗"
echo "║ Stage 0 → Stage 1 Incremental Compilation Workflow                 ║"
echo "╚════════════════════════════════════════════════════════════════════╝"
echo ""
echo "📋 Source Analysis:"
echo "   File: $SOURCE_FILE"
echo "   Output: $OUTPUT_BINARY"
echo ""

# Step 1: Analyze source file
echo "Step 1: Analyzing source file for feature usage..."
ANALYSIS=$(python3 "$SCRIPT_DIR/source_analyzer.py" "$SOURCE_FILE" 2>&1)
echo "$ANALYSIS"
echo ""

# Extract feature counts from analysis (simple grep-based approach)
FUNC_COUNT=$(echo "$ANALYSIS" | grep "fn_def" | grep -oE "[0-9]+" | head -1)
STRUCT_COUNT=$(echo "$ANALYSIS" | grep "struct_def" | grep -oE "[0-9]+" | head -1)
IF_COUNT=$(echo "$ANALYSIS" | grep "if_stmt" | grep -oE "[0-9]+" | head -1)
LOOP_COUNT=$(echo "$ANALYSIS" | grep "loop_stmt" | grep -oE "[0-9]+" | head -1)

echo "📊 Feature Summary:"
echo "   Functions:    $FUNC_COUNT"
echo "   Structs:      $STRUCT_COUNT"
echo "   If statements: $IF_COUNT"
echo "   Loop statements: $LOOP_COUNT"
echo ""

# Step 2: Check for --analyze flag
if [[ "$ANALYZE" == "--analyze" ]]; then
    echo "✓ Analysis mode: stopping here (--analyze flag set)"
    exit 0
fi

# Step 3: Check for --split flag
if [[ "$ANALYZE" == "--split" ]]; then
    echo "Step 2: Analyzing split strategies..."
    python3 "$SCRIPT_DIR/source_splitter.py" "$SOURCE_FILE"
    echo ""
    echo "✓ Split analysis mode: stopping here (--split flag set)"
    exit 0
fi

# Step 4: Attempt compilation with Stage 0
echo "Step 2: Attempting compilation with Stage 0..."
JDA0="${PROJECT_ROOT}/bootstrap/stage0/jda0"

if [[ ! -f "$JDA0" ]]; then
    echo "❌ Error: Stage 0 binary not found: $JDA0"
    echo "   Run: cd $PROJECT_ROOT/bootstrap/stage0 && make all"
    exit 1
fi

if "$JDA0" "$SOURCE_FILE" "$OUTPUT_BINARY" 2>&1; then
    echo ""
    echo "✅ Compilation successful!"
    echo "   Output: $(ls -lh "$OUTPUT_BINARY" | awk '{print $5, $9}')"
    
    # Try to run the binary if it's not the full jda1.jda
    if [[ -x "$OUTPUT_BINARY" ]]; then
        echo ""
        echo "Step 3: Testing compiled binary..."
        if timeout 2 "$OUTPUT_BINARY" > /tmp/jda_out.txt 2>&1; then
            OUTPUT=$(cat /tmp/jda_out.txt)
            echo "   Output: $OUTPUT"
            echo "   Exit code: 0"
        else
            EXIT_CODE=$?
            OUTPUT=$(cat /tmp/jda_out.txt 2>/dev/null || echo "(no output)")
            echo "   Output: $OUTPUT"
            echo "   Exit code: $EXIT_CODE"
        fi
        echo ""
    fi
    
    echo "🎉 Workflow complete!"
    
    # Self-hosting check
    if [[ "$(basename "$SOURCE_FILE")" == "jda1.jda" ]]; then
        echo ""
        echo "📌 Self-hosting note:"
        echo "   This Stage 1 binary can now compile Jda code."
        echo "   Next step: Test self-hosting with:"
        echo "   $OUTPUT_BINARY $SOURCE_FILE jda1_selfhost"
    fi
else
    EXIT_CODE=$?
    echo ""
    echo "❌ Compilation failed with Stage 0"
    echo "   Stage 0 may not yet support all features in this source file."
    echo ""
    echo "📌 Feature gap analysis (from step 1):"
    echo "   Missing critical features:"
    echo "   - Functions: $FUNC_COUNT uses"
    echo "   - Structs: $STRUCT_COUNT uses"
    echo "   - If statements: $IF_COUNT uses"
    echo "   - Loop statements: $LOOP_COUNT uses"
    echo ""
    echo "💡 To track progress, run:"
    echo "   $0 --analyze $SOURCE_FILE"
    echo ""
    exit $EXIT_CODE
fi
