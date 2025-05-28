#!/bin/bash

# Create SSL certificates for localhost development
set -e

CERT_DIR="$HOME/.config/lbnl-data-repository/ssl"
mkdir -p "$CERT_DIR"
cd "$CERT_DIR"

echo "Generating SSL certificates for localhost development..."

# Generate CA private key
openssl genrsa -out ca-key.pem 4096

# Generate CA certificate
openssl req -new -x509 -sha256 -key ca-key.pem -out ca.pem -days 3650 \
  -subj "/C=US/ST=California/L=Berkeley/O=LBNL/OU=Development/CN=LBNL-Dev-CA"

# Generate server private key
openssl genrsa -out server-key.pem 4096

# Generate server certificate request
openssl req -new -key server-key.pem -out server.csr \
  -subj "/C=US/ST=California/L=Berkeley/O=LBNL/OU=Development/CN=localhost"

# Create extensions file for SAN
cat > server.ext << EOF
subjectAltName = DNS:localhost,DNS:*.localhost,IP:127.0.0.1,DNS:search,DNS:cache,DNS:db,DNS:mq
keyUsage = keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth, clientAuth
EOF

# Generate server certificate
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -sha256 -out server.pem -days 3650 -extfile server.ext

# Generate client certificate for OpenSearch admin
openssl genrsa -out admin-key.pem 4096
openssl req -new -key admin-key.pem -out admin.csr \
  -subj "/C=US/ST=California/L=Berkeley/O=LBNL/OU=Development/CN=admin"
openssl x509 -req -in admin.csr -CA ca.pem -CAkey ca-key.pem \
  -CAcreateserial -sha256 -out admin.pem -days 3650

# Set proper permissions
chmod 600 ca-key.pem server-key.pem admin-key.pem
chmod 644 ca.pem server.pem admin.pem server.csr server.ext

echo "Certificates generated successfully!"
echo "To trust the CA in your browser, import: $CERT_DIR/ca.pem"
echo ""
echo "Certificate files created:"
echo "- CA Certificate: ca.pem"
echo "- Server Certificate: server.pem"
echo "- Server Private Key: server-key.pem"
echo "- Admin Certificate: admin.pem"
echo "- Admin Private Key: admin-key.pem"

