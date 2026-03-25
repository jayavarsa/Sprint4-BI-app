"""
BI Platform - Test Suite
Owner: Premapriya (QA)

Run:  pytest tests/ -v
"""

import pytest
import json
import sys
import os

# Make sure the src directory is on the path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../src"))

from app import app


# ── Fixtures ───────────────────────────────────────────────────

@pytest.fixture
def client():
    """Create a test client for the Flask app."""
    app.config["TESTING"] = True
    with app.test_client() as c:
        yield c


# ── Tests: Core Endpoints ──────────────────────────────────────

class TestHealthEndpoint:
    def test_health_returns_200(self, client):
        response = client.get("/health")
        assert response.status_code == 200

    def test_health_returns_json(self, client):
        response = client.get("/health")
        data = json.loads(response.data)
        assert data["status"] == "healthy"

    def test_health_has_uptime(self, client):
        response = client.get("/health")
        data = json.loads(response.data)
        assert "uptime_seconds" in data
        assert data["uptime_seconds"] >= 0


class TestVersionEndpoint:
    def test_version_returns_200(self, client):
        response = client.get("/version")
        assert response.status_code == 200

    def test_version_has_version_field(self, client):
        response = client.get("/version")
        data = json.loads(response.data)
        assert "version" in data

    def test_version_has_client_field(self, client):
        response = client.get("/version")
        data = json.loads(response.data)
        assert "client" in data


class TestIndexEndpoint:
    def test_index_returns_200(self, client):
        response = client.get("/")
        assert response.status_code == 200

    def test_index_shows_service_name(self, client):
        response = client.get("/")
        data = json.loads(response.data)
        assert data["service"] == "BI Platform"


class TestDashboardEndpoint:
    def test_dashboard_returns_200(self, client):
        response = client.get("/api/dashboard")
        assert response.status_code == 200

    def test_dashboard_has_kpis(self, client):
        response = client.get("/api/dashboard")
        data = json.loads(response.data)
        assert "kpis" in data
        assert "total_revenue" in data["kpis"]

    def test_dashboard_has_client(self, client):
        response = client.get("/api/dashboard")
        data = json.loads(response.data)
        assert "client" in data


class TestReadinessEndpoint:
    def test_readiness_returns_200(self, client):
        response = client.get("/ready")
        assert response.status_code == 200

    def test_readiness_returns_ready_true(self, client):
        response = client.get("/ready")
        data = json.loads(response.data)
        assert data["ready"] is True


class TestErrorHandling:
    def test_404_returns_json(self, client):
        response = client.get("/nonexistent-path")
        assert response.status_code == 404
        data = json.loads(response.data)
        assert "error" in data
