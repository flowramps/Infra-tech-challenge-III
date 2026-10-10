"""Generic service used to build the sample microservices chain.

The same image runs as frontend, orders and inventory. The role of each
instance comes from environment variables:

    SERVICE_NAME     name reported in metrics, logs and traces
    SERVICE_VERSION  version label (used by the canary release)
    DOWNSTREAMS      comma separated URLs called on every request
    LATENCY_MS       mean simulated processing time
    FAULT_RATE       fraction of requests answered with HTTP 500

Telemetry:
    metrics  Prometheus format on METRICS_PORT (/metrics), with trace exemplars
    logs     JSON on stdout, including trace_id/span_id
    traces   OTLP/gRPC to OTEL_EXPORTER_OTLP_ENDPOINT
"""

import asyncio
import json
import logging
import os
import random
import sys
import time
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from prometheus_client import Counter, Histogram, start_http_server

SERVICE_NAME = os.getenv("SERVICE_NAME", "service")
SERVICE_VERSION = os.getenv("SERVICE_VERSION", "v1")
DOWNSTREAMS = [url for url in os.getenv("DOWNSTREAMS", "").split(",") if url]
LATENCY_MS = float(os.getenv("LATENCY_MS", "20"))
FAULT_RATE = float(os.getenv("FAULT_RATE", "0"))
METRICS_PORT = int(os.getenv("METRICS_PORT", "9464"))
UNOBSERVED_PATHS = {"/healthz", "/readyz"}

# --- traces -----------------------------------------------------------------
tracer_provider = TracerProvider(
    resource=Resource.create(
        {"service.name": SERVICE_NAME, "service.version": SERVICE_VERSION}
    )
)
tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
trace.set_tracer_provider(tracer_provider)
HTTPXClientInstrumentor().instrument()


# --- logs -------------------------------------------------------------------
class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "ts": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname.lower(),
            "service": SERVICE_NAME,
            "version": SERVICE_VERSION,
            "msg": record.getMessage(),
        }
        span_context = trace.get_current_span().get_span_context()
        if span_context.is_valid:
            entry["trace_id"] = format(span_context.trace_id, "032x")
            entry["span_id"] = format(span_context.span_id, "016x")
        entry.update(getattr(record, "fields", {}))
        return json.dumps(entry)


handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
log = logging.getLogger("app")
log.addHandler(handler)
log.setLevel(logging.INFO)
log.propagate = False

# --- metrics ----------------------------------------------------------------
REQUESTS = Counter(
    "http_server_requests",
    "HTTP requests handled.",
    ["app", "version", "method", "route", "code"],
)
DURATION = Histogram(
    "http_server_request_duration_seconds",
    "HTTP request duration.",
    ["app", "version", "method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)


# --- application ------------------------------------------------------------
@asynccontextmanager
async def lifespan(app: FastAPI):
    start_http_server(METRICS_PORT)
    app.state.client = httpx.AsyncClient(timeout=httpx.Timeout(2.0))
    log.info("service started", extra={"fields": {"downstreams": DOWNSTREAMS}})
    yield
    await app.state.client.aclose()
    tracer_provider.shutdown()


app = FastAPI(title=SERVICE_NAME, lifespan=lifespan)


@app.middleware("http")
async def observe(request: Request, call_next):
    if request.url.path in UNOBSERVED_PATHS:
        return await call_next(request)

    start = time.perf_counter()
    response = await call_next(request)
    elapsed = time.perf_counter() - start

    route = getattr(request.scope.get("route"), "path", "unmatched")
    span_context = trace.get_current_span().get_span_context()
    exemplar = (
        {"trace_id": format(span_context.trace_id, "032x")}
        if span_context.is_valid
        else None
    )

    REQUESTS.labels(
        SERVICE_NAME, SERVICE_VERSION, request.method, route, str(response.status_code)
    ).inc(exemplar=exemplar)
    DURATION.labels(SERVICE_NAME, SERVICE_VERSION, request.method, route).observe(
        elapsed, exemplar=exemplar
    )
    log.info(
        "request handled",
        extra={
            "fields": {
                "method": request.method,
                "path": request.url.path,
                "status": response.status_code,
                "duration_ms": round(elapsed * 1000, 2),
            }
        },
    )
    return response


@app.get("/")
async def handle(request: Request):
    if LATENCY_MS > 0:
        await asyncio.sleep(random.expovariate(1 / LATENCY_MS) / 1000)

    if random.random() < FAULT_RATE:
        log.warning("injected fault")
        return JSONResponse({"service": SERVICE_NAME, "error": "injected fault"}, 500)

    calls = []
    for url in DOWNSTREAMS:
        try:
            response = await request.app.state.client.get(url)
            response.raise_for_status()
            calls.append(response.json())
        except httpx.HTTPError as exc:
            log.error(
                "downstream call failed",
                extra={"fields": {"downstream": url, "error": str(exc)}},
            )
            return JSONResponse(
                {"service": SERVICE_NAME, "error": f"downstream {url} failed"}, 502
            )

    return {"service": SERVICE_NAME, "version": SERVICE_VERSION, "downstream": calls}


@app.get("/healthz")
async def healthz():
    return {"status": "ok"}


@app.get("/readyz")
async def readyz():
    return {"status": "ready"}


FastAPIInstrumentor.instrument_app(app, excluded_urls="healthz,readyz")
