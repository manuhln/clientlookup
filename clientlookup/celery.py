import os
from celery import Celery

# Set Django settings module
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'clientlookup.settings')

app = Celery('clientlookup')

app.config_from_object('django.conf:settings', namespace='CELERY')
app.autodiscover_tasks()