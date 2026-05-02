#!/bin/sh
# jdavm installer — one-line setup for the Jda Version Manager
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jdalang/jda-lang/main/install-jdavm.sh | sh
#
# This downloads jdavm, installs it to ~/.jdavm, sets up PATH,
# and optionally installs the latest Jda version.

set -e

REPO="jdalang/jda-lang"
JDAVM_DIR="${JDAVM_DIR:-$HOME/.jdavm}"

# Colors
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ]; then
    G='\033[0;32m' B='\033[0;34m' BD='\033[1m' RS='\033[0m'
else
    G='' B='' BD='' RS=''
fi

info()  { printf "${B}info${RS}  %s\n" "$1"; }
ok()    { printf "${G}  ok${RS}  %s\n" "$1"; }
die()   { printf "\033[0;31merr \033[0m  %s\n" "$1" >&2; exit 1; }

# Fetch tool
if command -v curl >/dev/null 2>&1; then
    FETCH_OUT="curl -fsSL -o"
elif command -v wget >/dev/null 2>&1; then
    FETCH_OUT="wget -qO"
else
    die "curl or wget is required"
fi

printf "\n${BD}Jda Version Manager (jdavm) Installer${RS}\n\n"

# Download jdavm
info "Downloading jdavm..."
mkdir -p "$JDAVM_DIR/bin" "$JDAVM_DIR/versions"

$FETCH_OUT "$JDAVM_DIR/bin/jdavm" \
    "https://raw.githubusercontent.com/$REPO/main/tools/jdavm" \
    || die "Failed to download jdavm"

chmod +x "$JDAVM_DIR/bin/jdavm"
ok "Downloaded jdavm"

# Run self-install (sets up PATH, migrates ~/.jda)
export PATH="$JDAVM_DIR/bin:$PATH"
"$JDAVM_DIR/bin/jdavm" install

# Ask about installing latest (non-interactive: just tell them)
echo ""
printf "To install Jda:\n"
printf "  ${BD}jdavm install latest${RS}\n"
printf "  ${BD}jdavm install 0.2.0${RS}\n"
echo ""
