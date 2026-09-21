#!/usr/bin/env python3
"""
YuE Python Studio - Application Launcher
"""
import sys
import os
import webbrowser
import argparse
from pathlib import Path

# Ensure project root is in sys.path
BASE_DIR = Path(__file__).resolve().parent
if str(BASE_DIR) not in sys.path:
    sys.path.insert(0, str(BASE_DIR))

import uvicorn
from backend.server.app import create_app
from backend import BUILD_NUMBER, __version__

def main():
    parser = argparse.ArgumentParser(description="YuE Python Studio")
    parser.add_argument("--host", type=str, default="127.0.0.1", help="Host address to bind")
    parser.add_argument("--port", type=int, default=7865, help="Port to listen on")
    parser.add_argument("--no-browser", action="store_true", help="Do not automatically launch web browser")
    args = parser.parse_args()

    print(f"==================================================")
    print(f"   YuE Python Studio - Build {BUILD_NUMBER} (v{__version__})")
    print(f"   Full-Song Music Generation Pipeline Studio")
    print(f"==================================================")
    print(f"Server starting on http://{args.host}:{args.port}")

    if not args.no_browser:
        def open_browser():
            import time
            time.sleep(1.2)
            webbrowser.open(f"http://{args.host}:{args.port}")
        import threading
        threading.Thread(target=open_browser, daemon=True).start()

    app = create_app()
    uvicorn.run(app, host=args.host, port=args.port, log_level="info")

if __name__ == "__main__":
    main()
