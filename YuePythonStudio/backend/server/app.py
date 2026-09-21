import os
from pathlib import Path
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from .api_routes import router as api_router

def create_app() -> FastAPI:
    app = FastAPI(
        title="YuE Python Studio",
        description="Full-Song Dual-Track Music Generation Pipeline Studio in Python",
        version="1.0.0"
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.middleware("http")
    async def add_no_cache_header(request, call_next):
        response = await call_next(request)
        response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
        response.headers["Pragma"] = "no-cache"
        response.headers["Expires"] = "0"
        return response

    app.include_router(api_router)

    frontend_dir = Path(__file__).resolve().parent.parent.parent / "frontend"
    static_dir = frontend_dir / "static"

    if static_dir.exists():
        app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

    @app.get("/")
    def serve_index():
        from fastapi.responses import FileResponse
        index_file = frontend_dir / "index.html"
        return FileResponse(str(index_file))

    return app
