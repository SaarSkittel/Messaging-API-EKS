
from rest_framework_simplejwt.tokens import RefreshToken, AccessToken
from rest_framework_simplejwt.exceptions import TokenError
def get_tokens_for_user(user):
    refresh = RefreshToken.for_user(user)
    # Copy the email claim onto the refresh token so downstream services can mint compatible access tokens from it.
    refresh["email"] = user.email
    access = refresh.access_token
    return {
        'refresh': str(refresh),
        'access': str(access),
    }
def verify_access_token(token: str) -> dict:
    validated = AccessToken(token)
    return {
        "user_id": validated["user_id"],
        "email": validated.get("email", "")
    }
