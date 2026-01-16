# --- Stage 1: Build Stage ---
FROM golang:1.25.6-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git make

# 1. Clone CoreDNS source
WORKDIR /go/src/github.com/coredns/coredns
RUN git clone --depth 1 --branch v1.13.2 https://github.com/coredns/coredns.git .

# 2. Add your external plugin(s)
# Replace 'example' and the URL with your actual plugin details
RUN echo "acme:github.com/chinzhiweiblank/coredns-acme" >> plugin.cfg

# 3. Fetch dependencies and generate source
RUN go get github.com/chinzhiweiblank/coredns-acme
RUN go generate
RUN make

# --- Stage 2: Runtime Stage ---
FROM alpine:latest

# Install ca-certificates for TLS-based plugins
RUN apk add --no-cache ca-certificates

# Copy the compiled binary from the builder stage
COPY --from=builder /go/src/github.com/coredns/coredns/coredns /coredns

# Expose DNS ports
EXPOSE 53 53/udp

# Run CoreDNS
ENTRYPOINT ["/coredns"]
CMD ["-conf", "/etc/coredns/Corefile"]
