from grpc_client.auth_client import AuthGRPCClient
from rest_framework import status
from rest_framework.response import Response
from rest_framework.renderers import JSONRenderer

class Middleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        return self.get_response(request)

    def process_view(self, request, view_func, view_args, view_kwargs):
        excluded_paths = ["/api/auth/", "/api/register/", "/api/token/", "/api/test"]
        excluded_prefixes = ["/admin/", "/__debug__/", "/status/"]

        is_excluded = request.path in excluded_paths or any(
            request.path.startswith(p) for p in excluded_prefixes
        )
        if is_excluded:
            return None

        access_token = request.headers.get("Authorization")
        if not access_token:
            return self._error(status.HTTP_400_BAD_REQUEST)

        try:
            grpc_response = AuthGRPCClient.verify_token(access_token)
            print(f"DEBUG grpc_response: is_valid={grpc_response.is_valid} error={grpc_response.error}")

            if not grpc_response.is_valid:
                return self._error(status.HTTP_401_UNAUTHORIZED)

            request.user_id = grpc_response.user_id
            request.user_email = grpc_response.email

        except Exception as e:
            print(f"DEBUG exception: {type(e).__name__}: {str(e)}")  
            return self._error(status.HTTP_503_SERVICE_UNAVAILABLE)

        return None

    def _error(self, http_status):
        response = Response(status=http_status)
        response.accepted_renderer = JSONRenderer()
        response.accepted_media_type = "application/json"
        response.renderer_context = {}
        return response