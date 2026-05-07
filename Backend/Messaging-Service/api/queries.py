# queries.py
from django.db import transaction, IntegrityError
from django.db.models import Max
from datetime import datetime
from .models import Conversation, Message
from .serializers import MessageSerializer

MAX_RETRIES = 3

def write_message(sender_id, receiver_id, data):
    # safely create conversations
    try:
        with transaction.atomic():
            sender_conv, _ = Conversation.objects.get_or_create(
                user=sender_id,
                friend=receiver_id
            )
    except IntegrityError:
        sender_conv = Conversation.objects.get(user=sender_id, friend=receiver_id)

    try:
        with transaction.atomic():
            receiver_conv, _ = Conversation.objects.get_or_create(
                user=receiver_id,
                friend=sender_id
            )
    except IntegrityError:
        receiver_conv = Conversation.objects.get(user=receiver_id, friend=sender_id)

    # write with retry on sort collision
    _write_with_retry(sender_conv, sender_id, receiver_id, data, unread=True)
    _write_with_retry(receiver_conv, sender_id, receiver_id, data, unread=False)


def _write_with_retry(conversation, sender_id, receiver_id, data, unread, retries=0):
    try:
        with transaction.atomic():
            # get max sort value atomically
            max_sort = Message.objects.filter(
                conversation=conversation
            ).aggregate(Max("sort"))["sort__max"]
            sort = (max_sort + 1) if max_sort is not None else 1

            Message.objects.create(
                conversation=conversation,
                sort=sort,
                sender=str(sender_id),
                receiver=str(receiver_id),
                subject=data["subject"],
                message=data["message"],
                date=datetime.now().date(),
                unread=unread
            )
    except IntegrityError:
        # sort collision — retry
        if retries < MAX_RETRIES:
            _write_with_retry(conversation, sender_id, receiver_id, data, unread, retries + 1)
        else:
            raise Exception("Failed to write message after max retries")
def get_all_messages(user_id, friend_id):
    messages = Message.objects.select_related("conversation").filter(
        conversation__user=user_id,
        conversation__friend=friend_id
    )
    update_unread(messages)
    serializer = MessageSerializer(messages, many=True)
    return serializer.data

def get_all_unread_messages(user_id, friend_id):
    messages = Message.objects.select_related("conversation").filter(
        conversation__user=user_id,
        conversation__friend=friend_id,
        unread=True
    )
    serializer = MessageSerializer(messages, many=True)
    update_unread(messages)
    return serializer.data

def read_message(user_id, friend_id):
    message = Message.objects.select_related("conversation").filter(
        conversation__user=user_id,
        conversation__friend=friend_id
    ).order_by("sort").last()
    message.change_unread()
    message.save()
    serializer = MessageSerializer(message)
    return serializer.data

def delete_message(user_id, friend_id, message_position):
    _delete(user_id, friend_id, message_position)
    _delete(friend_id, user_id, message_position)

def _delete(user_id, friend_id, position):
    Message.objects.select_related("conversation").filter(
        conversation__user=user_id,
        conversation__friend=friend_id,
        sort=position
    ).delete()

def update_unread(messages):
    for message in messages:
        if message.unread:
            message.change_unread()
            message.save()