import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'generated'))

import grpc
import auth_pb2
import auth_pb2_grpc
from django.conf import settings

class AuthGRPCClient:
    _channel = None
    _stub = None

    @classmethod
    def get_stub(cls):
        if cls._channel is None:  # created once, never updated
            cls._channel = grpc.insecure_channel(settings.AUTH_GRPC_HOST)
            cls._stub = auth_pb2_grpc.AuthServiceStub(cls._channel)
        return cls._stub

   # grpc_client/auth_client.py
    @classmethod
    def verify_token(cls, access_token: str):
        try:
            stub = cls.get_stub()
            request = auth_pb2.VerifyTokenRequest(access_token=access_token)
            response = stub.VerifyAccessToken(request, timeout=5)
            return response
        except Exception as e:
            print(f"DEBUG gRPC error: {type(e).__name__}: {str(e)}")
            raise