import threading
from django.apps import AppConfig

class AuthConfig(AppConfig):
    name = "api"  # must match the actual app folder name

    def ready(self):
        from grpc_server.server import serve
        thread = threading.Thread(target=serve, daemon=True)
        thread.start()