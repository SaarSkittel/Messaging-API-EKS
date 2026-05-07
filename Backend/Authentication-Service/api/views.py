# views.py
from django.shortcuts import render
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from django.core.exceptions import PermissionDenied
from django.conf import settings
from django.contrib.auth import authenticate
from .jwt import get_tokens_for_user
from .queries import register as register_user  # rename to avoid conflict

@api_view(["POST"])
def authentication(request):
    user_name = request.data["username"]
    user_password = request.data["password"]
    if not user_name or not user_password:
        return Response(status=status.HTTP_400_BAD_REQUEST)
    try:
        user = authenticate(username=user_name, password=user_password)
        if user is not None:
            tokens = get_tokens_for_user(user)
            response = Response({"access_token": tokens["access"]})
            response.set_cookie(
                key="REFRESH_TOKEN",
                value=tokens["refresh"],
                httponly=True,
                secure=False,
                samesite="Lax"
            )
            return response
        return Response(status=status.HTTP_404_NOT_FOUND)
    except PermissionDenied:
        return Response(status=status.HTTP_403_FORBIDDEN)
    except Exception as e:
        print(f"Auth error: {e}")
        return Response(status=status.HTTP_500_INTERNAL_SERVER_ERROR)

@api_view(["POST"])
def register(request):
    username = request.data.get("username")
    email = request.data.get("email")
    password = request.data.get("password")

    if not username or not email or not password:
        return Response(status=status.HTTP_400_BAD_REQUEST)
    try:
        register_user(username, email, password)  # calls queries.register
        return Response(status=status.HTTP_201_CREATED)
    except Exception as e:
        return Response(
            {"error": str(e)},
            status=status.HTTP_409_CONFLICT
        )