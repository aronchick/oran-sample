#!/usr/bin/env bash
#
# Development Environment Setup
# Installs pre-commit hooks and Expanso CLI for local validation
#

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

step() { echo -e "\n${BLUE}▶${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }

echo ""
echo "=================================="
echo "  O-RAN Demo - Dev Environment"
echo "=================================="

# Check for Python/pip
step "Checking Python installation..."
if ! command -v python3 &> /dev/null; then
    error "Python 3 not found. Please install Python 3."
    exit 1
fi
success "Python $(python3 --version | cut -d' ' -f2) found"

# Install pre-commit
step "Installing pre-commit..."
if ! command -v pre-commit &> /dev/null; then
    pip3 install --user pre-commit
    success "pre-commit installed"
else
    success "pre-commit already installed ($(pre-commit --version))"
fi

# Install Expanso CLI locally
step "Installing Expanso CLI to .bin/..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="$SCRIPT_DIR/.bin"

if [ ! -f "$BIN_DIR/expanso-cli" ]; then
    mkdir -p "$BIN_DIR"
    curl -fsSL https://get.expanso.io/cli/install.sh | EXPANSO_INSTALL_DIR="$BIN_DIR" bash
    success "Expanso CLI installed to $BIN_DIR"
else
    success "Expanso CLI already installed at $BIN_DIR/expanso-cli"
fi

# Add .bin to PATH for this session
export PATH="$BIN_DIR:$PATH"

# Install pre-commit hooks
step "Installing pre-commit hooks..."
pre-commit install
success "Pre-commit hooks installed"

# Verify setup
step "Verifying setup..."
echo ""
echo "  Installed tools:"
echo "    - pre-commit: $(pre-commit --version)"
echo "    - expanso-cli: $BIN_DIR/expanso-cli"
echo ""

# Run validation
step "Running initial validation..."
if pre-commit run --all-files; then
    success "All checks passed!"
else
    error "Some checks failed. Please fix the issues above."
    exit 1
fi

echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Pre-commit hooks will now run automatically on git commit."
echo "To run manually: pre-commit run --all-files"
