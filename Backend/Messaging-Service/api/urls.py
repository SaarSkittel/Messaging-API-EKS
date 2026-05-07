from django.urls import path
from. import views

urlpatterns=[
    path("write",views.write_message),
    path("get_all/",views.get_all_messages),
    path("get_all_unread/",views.get_all_unread_messages),
    path("get_message",views.read_message),
    path("delete_message",views.delete_message),
    path("token",views.token),
    path("test",views.run_task),
    path("status/<str:task_id>",views.get_status),
]