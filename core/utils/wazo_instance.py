import requests
from django.core.cache import cache

from requests.auth import HTTPBasicAuth


class WazoClient:
    def __init__(self, hostname, username, password):
        self.hostname = hostname.rstrip('/')
        self.username = username
        self.password = password
        self._token = None

    def _get_url(self, endpoint):
        """Build full URL for API endpoint"""
        return f"https://{self.hostname}/api/{endpoint}"

    def _get_token(self):
        """Get or refresh authentication token"""
        token = cache.get(f"{self.hostname}_wazo_instance_token")
        # Reset token for debug purposes
        # [ ] todo: comment this line
        # token = None

        if token is None:
            try:
                url = self._get_url("auth/0.1/token")
                response = requests.post(
                    url,
                    auth=HTTPBasicAuth(self.username, self.password),
                    json={
                        'access_type': 'online',
                        'expiration': 7200
                    }
                )

                if response.status_code == 200:
                    token = response.json()['data']['token']
                    token_bytes = bytes(token, "ascii")
                    cache.set(f"{self.hostname}_wazo_instance_token",
                          token_bytes, timeout=3540)
                    self._token = token
                else:
                    print(
                        f"Token error: {response.status_code} - {response.text}")
                    return None
            except requests.exceptions.RequestException as e:
                print(f"Request failed: {e}")
                return None
        else:
            self._token = token.decode("ascii")

        return self._token

    def _make_request(self, method, endpoint, tenant_uuid=None, **kwargs):
        """Make authenticated request to Wazo API"""
        token = self._get_token()
        if not token:
            return None

        url = self._get_url(endpoint)
        headers = kwargs.pop('headers', {})
        headers['x-auth-token'] = token

        if tenant_uuid:
            headers['Wazo-Tenant'] = tenant_uuid

        print(f"Request URL: {url}")
        try:
            response = requests.request(method, url, headers=headers, **kwargs)
            if response.ok:
                return True if response.status_code == 204 else response.json()
            else:
                print(f"API Error: {response.status_code} - {response.text}")
                return None
        except requests.exceptions.RequestException as e:
            print(f"Request failed: {e}")
            raise
            # return None

    def get_users(self, params={}) -> dict :
        result = self._make_request(
            'GET', f'auth/0.1/users?recurse=true', tenant_uuid=None, params=params)
        return result or {}