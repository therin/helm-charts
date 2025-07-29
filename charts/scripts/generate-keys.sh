#!/bin/bash

# Xray Reality Key Generation Script
# This script generates the necessary keys and UUIDs for Xray Reality protocol

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to generate UUID
generate_uuid() {
    if command_exists uuidgen; then
        uuidgen | tr '[:upper:]' '[:lower:]'
    elif command_exists python3; then
        python3 -c "import uuid; print(str(uuid.uuid4()))"
    elif command_exists python; then
        python -c "import uuid; print(str(uuid.uuid4()))"
    else
        # Fallback: generate a pseudo-UUID
        print_warning "No UUID generator found. Using fallback method."
        openssl rand -hex 16 | sed 's/\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)\(..\)/\1\2\3\4-\5\6-\7\8-\9\10-\11\12\13\14\15\16/'
    fi
}

# Function to generate Reality keys
generate_reality_keys() {
    if command_exists xray; then
        print_info "Generating Reality key pair using xray..."
        xray x25519
    elif command_exists openssl; then
        print_info "Generating Reality key pair using openssl..."
        # Generate private key
        private_key=$(openssl genpkey -algorithm X25519 | openssl pkey -text -noout | grep -A 3 "priv:" | tail -n +2 | tr -d ' \n:' | head -c 64)
        # Generate public key from private key
        echo "$private_key" | xxd -r -p | openssl pkey -inform raw -keyform raw -pubin -pubout -outform DER | tail -c 32 | xxd -p -c 32
        echo "Private Key: $private_key"
        echo "Public Key: $(echo "$private_key" | xxd -r -p | openssl pkey -inform raw -keyform raw -pubin -pubout -outform DER | tail -c 32 | xxd -p -c 32)"
    else
        print_error "Neither xray nor openssl found. Cannot generate Reality keys."
        print_info "Please install xray-core or openssl to generate Reality keys."
        return 1
    fi
}

# Function to generate short IDs
generate_short_ids() {
    local count=${1:-3}
    print_info "Generating $count short IDs..."
    for i in $(seq 1 $count); do
        if command_exists openssl; then
            openssl rand -hex 8
        else
            # Fallback using /dev/urandom
            head -c 8 /dev/urandom | xxd -p
        fi
    done
}

# Function to generate complete configuration
generate_complete_config() {
    print_info "Generating complete Xray Reality configuration..."
    echo
    echo "=== XRAY REALITY CONFIGURATION ==="
    echo
    
    # Generate client UUIDs
    print_info "Client UUIDs:"
    for i in {1..2}; do
        uuid=$(generate_uuid)
        echo "  Client $i: $uuid"
    done
    echo
    
    # Generate Reality keys
    print_info "Reality Key Pair:"
    if command_exists xray; then
        key_output=$(xray x25519 2>/dev/null)
        echo "$key_output"
    else
        print_warning "xray command not found. Please install xray-core to generate proper Reality keys."
        echo "  Private Key: [GENERATE_WITH_XRAY_X25519]"
        echo "  Public Key: [GENERATE_WITH_XRAY_X25519]"
    fi
    echo
    
    # Generate short IDs
    print_info "Short IDs:"
    short_ids=$(generate_short_ids 3)
    echo "$short_ids" | sed 's/^/  /'
    echo
    
    # Generate SOCKS5 credentials
    print_info "SOCKS5 Credentials (optional):"
    echo "  Username: user$(openssl rand -hex 4)"
    echo "  Password: $(openssl rand -base64 12)"
    echo
    
    print_success "Configuration generated successfully!"
    echo
    print_info "Next steps:"
    echo "1. Update your values.yaml file with the generated values"
    echo "2. Choose a target domain for Reality (e.g., www.microsoft.com, www.cloudflare.com)"
    echo "3. Deploy the Helm chart: helm install xray-proxy ./xray-proxy"
    echo "4. Configure your client with the generated credentials"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -u, --uuid          Generate a single UUID"
    echo "  -r, --reality       Generate Reality key pair"
    echo "  -s, --short-ids N   Generate N short IDs (default: 3)"
    echo "  -c, --complete      Generate complete configuration"
    echo
    echo "Examples:"
    echo "  $0 --complete       Generate complete configuration"
    echo "  $0 --uuid           Generate a single UUID"
    echo "  $0 --reality        Generate Reality key pair"
    echo "  $0 --short-ids 5    Generate 5 short IDs"
}

# Main script logic
main() {
    case "${1:-}" in
        -h|--help)
            show_usage
            ;;
        -u|--uuid)
            generate_uuid
            ;;
        -r|--reality)
            generate_reality_keys
            ;;
        -s|--short-ids)
            count=${2:-3}
            generate_short_ids "$count"
            ;;
        -c|--complete|"")
            generate_complete_config
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command_exists openssl; then
        missing_deps+=("openssl")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_warning "Missing dependencies: ${missing_deps[*]}"
        print_info "Please install the missing dependencies for full functionality."
    fi
    
    if command_exists xray; then
        print_success "xray-core found - full functionality available"
    else
        print_warning "xray-core not found - some features will use fallback methods"
        print_info "Install xray-core for optimal key generation: https://github.com/XTLS/Xray-core"
    fi
}

# Run dependency check and main function
check_dependencies
main "$@"