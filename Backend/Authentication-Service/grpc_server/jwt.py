
from rest_framework_simplejwt.tokens import RefreshToken, AccessToken
from rest_framework_simplejwt.exceptions import TokenError
def get_tokens_for_user(user):
    refresh = RefreshToken.for_user(user)
    return {
        'refresh': str(refresh),
        'access': str(refresh.access_token),
    }
def verify_access_token(token: str) -> dict:
    validated = AccessToken(token)
    return {
        "user_id": validated["user_id"],
        "email": validated.get("email", "")
    }