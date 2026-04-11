# ============================================================
# QSN Rugby Agent — Dockerfile
# ============================================================
# WHAT THIS DOES (plain English):
#   Stage 1 (builder): Start with Python, install all libraries
#   Stage 2 (runtime): Copy ONLY what's needed into a tiny image
#   Result: A small, fast, secure container for your agent
#
# TWO-STAGE BUILD = smaller final image (fewer security risks)
# ============================================================

# ---- STAGE 1: Builder ----
# "Give me a full Python environment to install packages"
FROM python:3.11-slim AS builder

WORKDIR /build

# Copy requirements first — Docker caches this layer
# If requirements.txt hasn't changed, Docker skips reinstalling
COPY requirements.txt .

# Install dependencies into /install folder (not system Python)
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ---- STAGE 2: Runtime ----
# "Give me a clean, minimal Python to run the app"
FROM python:3.11-slim AS runtime

# Who built this image (good practice for enterprise registries)
LABEL maintainer="Jeff — QSN Rugby / Rizing LLC"
LABEL version="1.0"
LABEL description="QSN Rugby LangGraph Multi-Agent Content Factory"

WORKDIR /app

# Copy installed packages from builder stage
COPY --from=builder /install /usr/local

# Copy ONLY the application code (not build artifacts)
COPY qsn_agent.py .

# ---- SECURITY: Don't run as root ----
# Running as root inside a container is a security risk.
# Create a non-root user for the agent process.
RUN useradd --no-create-home --shell /bin/false qsnuser
USER qsnuser

# ---- ENVIRONMENT ----
# API key comes in at runtime via K8s Secret — NEVER hardcode it here
# ENV ANTHROPIC_API_KEY is set by Kubernetes, not in this file

# ---- HEALTH CHECK ----
# Docker itself will check if the container is healthy
# If /health returns non-200 three times, Docker marks it unhealthy
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/health')" || exit 1

# ---- PORT ----
# The health check server listens on 8080
EXPOSE 8080

# ---- START COMMAND ----
# --health starts the /health server (for K8s liveness probes)
CMD ["python", "qsn_agent.py", "--health"]
