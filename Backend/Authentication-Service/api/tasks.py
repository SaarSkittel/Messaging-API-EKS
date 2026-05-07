import time
from typing import Dict
from server.celery import app
from .queries import register
from celery import shared_task


@shared_task
def register_task(username,email, password):
    register(username,email,password)
    return True

