from .models import WazoUserCache
from .serializers import AuthenticationSerializer

# import base64
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
# from django.db import IntegrityError

from django.core.cache import cache

# import requests
# from requests.auth import HTTPBasicAuth


@api_view(http_method_names=['GET'])
def authenticate(request, username):
    try:
        # Check if the user already exists in the cache
        try:
            cached_user = WazoUserCache.objects.get(username=username)
            # cache it in redis
            cache_key = f"username:{username}"
            cache.set(cache_key, cached_user.platform_hostname, timeout=60*10)
            return Response(data=cached_user.platform_hostname, status=status.HTTP_200_OK)
        except WazoUserCache.DoesNotExist:
            return Response(data='error', status=status.HTTP_404_NOT_FOUND)
        
        # platforms_list = ["node10.voxsun.net", "node11.voxsun.net", "node12.voxsun.net", "node13.voxsun.net"]
        
        # for platform in platforms_list:
        #     url = f"https://{platform}/api/auth/0.1/token"
        #     data = {
        #         "backend": "wazo_user",
        #         "access_type": "online",
        #         "expiration": 7200,
        #     }
        #     response = requests.post(url, auth=HTTPBasicAuth(username, password), json=data, timeout=10)
            # if response.status_code == 200:
            #     result = response.json()['data']
            #     _headers = {
            #         "X-Auth-Token": result['token']
            #     }
            #     # check if this is an actual web or app user
            #     response_user = requests.get(f"https://{platform}/api/confd/1.1/users/{result['auth_id']}", headers=_headers)
            #     # print(response_user.json())
            #     if response_user.status_code == 200:
            #         # create the user
            #         try:
            #             WazoUserCache.objects.create(username=username, platform_hostname=platform)
            #         except IntegrityError:
            #             pass
            #         response_headers = {
            #             'Wazo-Stack-Host': platform
            #         }
            #         return Response(data=platform, status=status.HTTP_200_OK, headers=response_headers)
            #     else:
            #         return Response(data='error', status=status.HTTP_200_OK)
        
        # return Response(data='error', status=status.HTTP_401_UNAUTHORIZED)
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
        
@api_view(http_method_names=['GET'])
def reset_password(request):
    pass
    