# Base Python image
FROM python:3.12.6-slim@sha256:ad48727987b259854d52241fac3bc633574364867b8e20aec305e6e7f4028b26 as base

# Builder stage to install dependencies
FROM base AS builder

WORKDIR /app

# Install git to clone the repo
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

# Clone Bank of Anthos repo to get requirements
RUN git clone https://github.com/GoogleCloudPlatform/bank-of-anthos.git /tmp/bank-of-anthos

# Install Python dependencies from the cloned repo
RUN pip install --prefix="/install" -r /tmp/bank-of-anthos/src/loadgenerator/requirements.txt

# Final stage
FROM base

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Add application code
COPY locustfile.py .

# Show Python logs as they occur
ENV PYTHONUNBUFFERED=0

# Enable gevent support in debugger
ENV GEVENT_SUPPORT=True

# Set fallback log level
ENV LOG_LEVEL info

ENV TEST=yes

# Start Locust load generator with default 100 users
ENTRYPOINT sh -c "echo 'Delaying start for 90s...'; sleep 90; locust --host=http://${FRONTEND_ADDR} --loglevel $LOG_LEVEL --headless --users=${USERS:-100} --run-time 1m --print-stats; echo 'Sleeping for 1 hour...'; sleep 3600"
