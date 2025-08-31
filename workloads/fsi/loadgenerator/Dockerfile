# Base Python image (pinned digest for reproducibility)
FROM python:3.12.6-slim@sha256:ad48727987b259854d52241fac3bc633574364867b8e20aec305e6e7f4028b26 AS base

# Builder stage
FROM base AS builder
WORKDIR /app

# Install build tools & git (only here, not in final)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    && rm -rf /var/lib/apt/lists/*

# Clone Bank of Anthos repo to get requirements
RUN git clone https://github.com/GoogleCloudPlatform/bank-of-anthos.git /tmp/bank-of-anthos

# Upgrade pip and install requirements into /install
RUN pip install --no-cache-dir --upgrade pip setuptools wheel \
    && pip install --prefix="/install" -r /tmp/bank-of-anthos/src/loadgenerator/requirements.txt

# Final stage
FROM base
WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application code
COPY locustfile.py indexing.py requirements.txt . 
COPY --chmod=755 entrypoint.sh /app/entrypoint.sh

# Install overlay-specific requirements
RUN pip install --no-cache-dir --upgrade pip setuptools wheel \
    && pip install --no-cache-dir -r requirements.txt

# Create non-root user
RUN useradd -m locust
USER locust

# Show Python logs as they occur
ENV PYTHONUNBUFFERED=0
ENV GEVENT_SUPPORT=True
ENV LOG_LEVEL=info
ENV TEST=yes

# Entrypoint script
ENTRYPOINT ["/app/entrypoint.sh"]
