from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from .models import WazoUserCache
from .serializers import AuthenticationSerializer
from django.db import IntegrityError

import requests
from requests.auth import HTTPBasicAuth


@api_view(http_method_names=['POST'])
def authenticate(request):
    try:
        serializer = AuthenticationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        username = serializer.validated_data['username']
        password = serializer.validated_data['password']
        
        # Check if the user already exists in the cache
        try:
            cached_user = WazoUserCache.objects.get(username=username)
            print("cache hit")
            return Response(data=cached_user.platform_hostname, status=status.HTTP_200_OK)
        except WazoUserCache.DoesNotExist:
            pass
        
        platforms_list = ["node10.voxsun.net", "node11.voxsun.net", "node12.voxsun.net", "node13.voxsun.net"]
        
        for platform in platforms_list:
            url = f"https://{platform}/api/auth/0.1/token"
            data = {
                "backend": "wazo_user",
                "access_type": "online",
                "expiration": 7200,
            }
            response = requests.post(url, auth=HTTPBasicAuth(username, password), json=data, timeout=10)
            if response.status_code == 200:
                result = response.json()['data']
                _headers = {
                    "X-Auth-Token": result['token']
                }
                # check if this is an actual web or app user
                response_user = requests.get(f"https://{platform}/api/confd/1.1/users/{result['auth_id']}", headers=_headers)
                print(response_user.json())
                if response_user.status_code == 200:
                    # create the user
                    try:
                        WazoUserCache.objects.create(username=username, platform_hostname=platform)
                    except IntegrityError:
                        pass
                    return Response(data=platform, status=status.HTTP_200_OK)
                else:
                    return Response(data='error', status=status.HTTP_200_OK)
        
        return Response(data='error', status=status.HTTP_401_UNAUTHORIZED)
    except Exception as e:
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)