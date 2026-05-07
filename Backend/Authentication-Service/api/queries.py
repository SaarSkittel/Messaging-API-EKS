# queries.py (auth service)
from django.contrib.auth.models import User
from django.db import IntegrityError, transaction

def register(username, email, password):
    try:
        with transaction.atomic():
            user = User.objects.create_user(
                username=username,
                email=email,
                password=password
            )
            return user
    except IntegrityError:
        # user already exists — return existing or raise
        raise Exception("Username or email already exists")
