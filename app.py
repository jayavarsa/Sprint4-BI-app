"""
BI Platform - Sample Application
Production-ready Flask app with health/version endpoints.
Owner: Premapriya (Containerization & QA)
"""

import os
import json
import time
import logging
from datetime import datetime
from flask import Flask, jsonify, request

# ── Logging setup ──────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s"
)
logger = logging.getLogger(__name__)

# ── App init ───────────────────────────────────────────────────
app = Flask(__name__)

# ── Config from environment variables ─────────────────────────
APP_VERSION   = os.getenv("APP_VERSION", "1.0.0")
CLIENT_ID     = os.getenv("CLIENT_ID", "default")
ENVIRONMENT   = os.getenv("ENVIRONMENT", "development")
APP_START_TIME = time.time()


# ── Routes ─────────────────────────────────────────────────────

@app.route("/")
def index():
    """Landing page — confirms the app is running."""
    return jsonify({
        "service": "BI Platform",
        "client": CLIENT_ID,
        "environment": ENVIRONMENT,
        "status": "running",
        "timestamp": datetime.utcnow().isoformat()
    })


@app.route("/health")
def health():
    """
    Health check endpoint.
    Used by Kubernetes liveness & readiness probes.
    Returns HTTP 200 when healthy.
    """
    uptime_seconds = round(time.time() - APP_START_TIME, 2)
    return jsonify({
        "status": "healthy",
        "uptime_seconds": uptime_seconds,
        "client": CLIENT_ID,
        "environment": ENVIRONMENT,
        "timestamp": datetime.utcnow().isoformat()
    }), 200


@app.route("/version")
def version():
    """
    Version endpoint.
    Used by CI/CD to confirm which image is deployed.
    """
    return jsonify({
        "version": APP_VERSION,
        "client": CLIENT_ID,
        "environment": ENVIRONMENT,
        "build_date": os.getenv("BUILD_DATE", "unknown"),
        "git_commit": os.getenv("GIT_COMMIT", "unknown")
    }), 200


@app.route("/api/dashboard")
def dashboard():
    """
    Sample BI dashboard endpoint.
    Returns mock KPI data per tenant.
    """
    # In production, replace with real DB queries scoped to CLIENT_ID
    mock_data = {
        "client": CLIENT_ID,
        "kpis": {
            "total_revenue": 1_250_000,
            "active_users": 4_320,
            "reports_generated": 892,
            "avg_load_time_ms": 143
        },
        "last_updated": datetime.utcnow().isoformat()
    }
    logger.info(f"Dashboard requested for client: {CLIENT_ID}")
    return jsonify(mock_data), 200


@app.route("/ready")
def readiness():
    """
    Readiness probe — confirm the app can serve traffic.
    Kubernetes will stop routing traffic here if this fails.
    """
    # Add real dependency checks here (DB ping, cache check, etc.)
    return jsonify({"ready": True}), 200


# ── Error handlers ─────────────────────────────────────────────

@app.errorhandler(404)
def not_found(e):
    return jsonify({"error": "Not found", "path": request.path}), 404


@app.errorhandler(500)
def server_error(e):
    logger.error(f"Server error: {e}")
    return jsonify({"error": "Internal server error"}), 500


# ── Entry point ────────────────────────────────────────────────

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    logger.info(f"Starting BI Platform v{APP_VERSION} for client '{CLIENT_ID}' on port {port}")
    # debug=False is mandatory for production
    app.run(host="0.0.0.0", port=port, debug=False)
