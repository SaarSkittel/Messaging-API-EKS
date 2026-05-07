# models.py
from django.db import models

class Conversation(models.Model):
    user = models.IntegerField()
    friend = models.IntegerField()

    class Meta:
        unique_together = ("user", "friend")

class Message(models.Model):
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE)
    sort = models.IntegerField(default=None)
    sender = models.CharField(max_length=200)
    receiver = models.CharField(max_length=200)
    subject = models.CharField(max_length=200)
    message = models.CharField(max_length=10000)
    date = models.DateField()
    unread = models.BooleanField()

    class Meta:
        unique_together = ("conversation", "sort")  # prevents duplicate sort values

    def change_unread(self):
        self.unread = False