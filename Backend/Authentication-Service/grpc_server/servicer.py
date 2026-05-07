import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'generated'))

import auth_pb2
import auth_pb2_grpc
from django.contrib.auth.models import User
from api.jwt import verify_access_token

class AuthServicer(auth_pb2_grpc.AuthServiceServicer):
    def VerifyAccessToken(self, request, context):
        try:
            payload = verify_access_token(request.access_token)

            try:
                user = User.objects.get(id=payload["user_id"])
            except User.DoesNotExist:
                return auth_pb2.VerifyTokenResponse(
                    is_valid=False,
                    error="User not found"
                )

            if user.email != payload["email"]:
                return auth_pb2.VerifyTokenResponse(
                    is_valid=False,
                    error="Email mismatch"
                )

            return auth_pb2.VerifyTokenResponse(
                is_valid=True,
                user_id=str(user.id),
                email=user.email
            )

        except Exception as e:
            return auth_pb2.VerifyTokenResponse(
                is_valid=False,
                error=str(e)
            )