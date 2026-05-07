
from rest_framework_simplejwt.tokens import RefreshToken, AccessToken
from rest_framework_simplejwt.exceptions import TokenError
def get_tokens_for_user(user):
    refresh = RefreshToken.for_user(user)
    access = refresh.access_token
    access["email"] = user.email  # add email to token
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