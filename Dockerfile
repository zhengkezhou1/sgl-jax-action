# Build stage
FROM golang:1.25-bookworm AS builder

WORKDIR /src

# Copy go mod and sum files first to leverage cache
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the application
# -o /bin/server: output binary name
RUN CGO_ENABLED=0 GOOS=linux go build -o /bin/server ./cmd/scheduler-server/main.go

# Final stage
FROM debian:bookworm-slim

# Install ca-certificates for HTTPS calls
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*

# Copy binary from builder
COPY --from=builder /bin/server /server
COPY --from=builder /src/config/templates /config/templates

EXPOSE 8080

ENTRYPOINT ["/server"]
