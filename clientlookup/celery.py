from celery import Celery
from django_celery_beat.models import IntervalSchedule, PeriodicTask

app = Celery('clientlookup', broker='redis://localhost:6379/0')

# Optional configuration, see the application user guide.
app.conf.update(
    result_expires=3600,
)

if __name__ == '__main__':
    app.start()