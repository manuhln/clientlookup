from django.db import models

class WazoUserCache(models.Model):
    id = models.AutoField(primary_key=True)
    username = models.CharField(max_length=255, unique=True)
    platform_hostname = models.CharField(max_length=255)
    
    class Meta:
        indexes = [
            models.Index(fields=['username']),
        ]