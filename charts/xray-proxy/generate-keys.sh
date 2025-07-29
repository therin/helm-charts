#!/bin/bash

# Simple key generation script for Xray proxy
# This script generates the necessary keys and IDs for Xray configuration

set -e

echo "🔑 Generating Xray configuration keys..."
echo

# Generate UUID for client
echo "📋 Client UUID:"
if command -v uuidgen >/dev/null 2>&1; then
    CLIENT_UUID=$(uuidgen | tr '[:upper:]' '[:lower:]')
    echo "   $CLIENT_UUID"
else
    echo "   ⚠️  uuidgen not found. Please install it or generate a UUID manually."
    echo "   You can use online UUID generators or install uuid-tools package."
fi

echo

# Generate Reality keys if xray is available
echo "🔐 Reality Key Pair:"
if command -v xray >/dev/null 2>&1; then
    KEYS=$(xray x25519)
    PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | cut -d' ' -f3)
    PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | cut -d' ' -f3)
    
    echo "   Private Key: $PRIVATE_KEY"
    echo "   Public Key:  $PUBLIC_KEY"
else
    echo "   ⚠️  xray command not found. Please install Xray-core to generate keys."
    echo "   Alternative: Use online Reality key generators or install Xray locally."
fi

echo

# Generate short ID
echo "🆔 Short ID:"
SHORT_ID=$(openssl rand -hex 4 2>/dev/null || echo "$(date +%s | sha256sum | head -c 8)")
echo "   $SHORT_ID"

echo
echo "✅ Key generation complete!"
echo
echo "📝 Next steps:"
echo "1. Copy values-example.yaml to my-values.yaml"
echo "2. Replace the placeholder values in my-values.yaml with the keys above"
echo "3. Install the chart: helm install xray-proxy ./charts/xray-proxy -f my-values.yaml"
echo

# Optionally create a values file template
if [ "$1" = "--create-values" ]; then
    echo "📄 Creating my-values.yaml with generated keys..."
    
    if [ -n "$CLIENT_UUID" ] && [ -n "$PRIVATE_KEY" ] && [ -n "$SHORT_ID" ]; then
        sed -e "s/12345678-1234-1234-1234-123456789abc/$CLIENT_UUID/g" \
            -e "s/EXAMPLE_PRIVATE_KEY_REPLACE_WITH_REAL_ONE/$PRIVATE_KEY/g" \
            -e "s/abcd1234/$SHORT_ID/g" \
            values-example.yaml > my-values.yaml
        
        echo "✅ Created my-values.yaml with your generated keys!"
        echo "📋 Your public key for clients: $PUBLIC_KEY"
    else
        echo "⚠️  Some keys could not be generated. Please update my-values.yaml manually."
    fi
fi