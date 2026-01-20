from django.urls import path
from . import views

urlpatterns = [
    path('auth/0.1/token', views.authenticate, name='authenticate'),
    path('auth/0.1/users/password/reset', views.reset_password, name='reset_password'),
]