# =============================================================================
# BI Platform — Dockerfile
# Owner: Premapriya (Containerization & QA)
#
# Multi-stage build:
#   Stage 1 (builder): Install Python deps in isolated layer
#   Stage 2 (runtime): Copy only what's needed → smaller, safer image
# =============================================================================

# ── Stage 1: Builder ──────────────────────────────────────────
FROM python:3.11-slim AS builder

# Set working directory
WORKDIR /build

# Copy only requirements first (Docker layer cache optimization)
# If requirements.txt doesn't change, this layer is cached → faster builds
COPY app/requirements.txt .

# Install dependencies into a prefix directory (not system Python)
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: Runtime ──────────────────────────────────────────
FROM python:3.11-slim AS runtime

# Security: run as non-root user
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

WORKDIR /app

# Copy installed packages from builder stage only
COPY --from=builder /install /usr/local

# Copy application source
COPY app/src/ .

# Set ownership to non-root user
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# ── Build-time metadata (injected by CI) ─────────────────────
ARG APP_VERSION=1.0.0
ARG BUILD_DATE=unknown
ARG GIT_COMMIT=unknown

# Make build args available as env vars at runtime
ENV APP_VERSION=${APP_VERSION} \
    BUILD_DATE=${BUILD_DATE} \
    GIT_COMMIT=${GIT_COMMIT} \
    # Tell Python not to write .pyc files (cleaner container)
    PYTHONDONTWRITEBYTECODE=1 \
    # Disable buffering so logs appear in real time
    PYTHONUNBUFFERED=1 \
    PORT=5000

# Expose port (documentation only — actual binding is in CMD)
EXPOSE 5000

# Health check — Docker itself will poll this
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000/health')"

# ── Start command ─────────────────────────────────────────────
# gunicorn: production WSGI server
# --workers 2: 2 worker processes (adjust per CPU count)
# --bind: listen on all interfaces
# --access-logfile -: log to stdout (Kubernetes picks this up)
CMD ["gunicorn", "--workers", "2", "--bind", "0.0.0.0:5000", "--access-logfile", "-", "--error-logfile", "-", "app:app"]
