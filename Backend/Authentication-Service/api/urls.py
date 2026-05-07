from django.urls import path
from. import views

urlpatterns=[
    path("login/",views.authentication),
    path("register/",views.register),
]