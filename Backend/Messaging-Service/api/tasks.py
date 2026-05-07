# tasks.py
from .queries import write_message, get_all_messages, get_all_unread_messages, delete_message, read_message
from celery import shared_task
import time

@shared_task
def create_task(task_type):
    time.sleep(int(task_type) * 10)
    return True

@shared_task
def get_all_messages_task(user_id, friend_id):
    return get_all_messages(user_id, friend_id)

@shared_task
def get_all_unread_messages_task(user_id, friend_id):
    return get_all_unread_messages(user_id, friend_id)

@shared_task
def write_message_task(user_id, receiver_id, data):
    write_message(user_id, receiver_id, data)
    return True

@shared_task
def read_message_task(user_id, friend_id):
    return read_message(user_id, friend_id)

@shared_task
def delete_message_task(user_id, friend_id, message_position):
    delete_message(user_id, friend_id, message_position)
    return True