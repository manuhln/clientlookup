local http = require "resty.http"
local redis = require "resty.redis"
local cjson = require "cjson.safe"

-- Globals
local _M = {}

-- ------------------------------------------------------------------
-- Redis helper
-- ------------------------------------------------------------------
local function get_redis()
    local red = redis:new()
    red:set_timeout(1000)

    local ok, err = red:connect("127.0.0.1", 6379)
    if not ok then
        ngx.log(ngx.ERR, "Redis connection failed: ", err)
        return nil
    end

    ngx.log(ngx.INFO, "Redis connection successful")
    return red
end

local function redis_keepalive(red)
    if not red then
        return
    end

    local ok, err = red:set_keepalive(10000, 100)
    if not ok then
        ngx.log(ngx.ERR, "Failed to set Redis keepalive: ", err)
    end
end

-- ------------------------------------------------------------------
-- Decode Authorization header (Basic auth)
-- ------------------------------------------------------------------
--- @return string|nil username
--- @return string|nil password
local function decode_authorization()
    local authorization = ngx.req.get_headers()["authorization"]
    
    ngx.log(ngx.INFO, "Authorization header: ", authorization or "NOT PRESENT")
    
    if not authorization then
        ngx.log(ngx.WARN, "No Authorization header found")
        return nil
    end

    local prefix = "Basic "
    if authorization:sub(1, #prefix) ~= prefix then
        ngx.log(ngx.WARN, "Authorization header doesn't start with 'Basic '")
        return nil
    end

    local encoded = authorization:sub(#prefix + 1)
    ngx.log(ngx.INFO, "Encoded credentials: ", encoded)
    
    local decoded = ngx.decode_base64(encoded)
    if not decoded then
        ngx.log(ngx.ERR, "Failed to decode base64 credentials")
        return nil
    end

    ngx.log(ngx.INFO, "Decoded credentials: ", decoded)
    
    local username, password = decoded:match("^([^:]+):(.+)$")
    
    if username then
        ngx.log(ngx.INFO, "Extracted username: ", username)
    else
        ngx.log(ngx.WARN, "Failed to extract username from decoded credentials")
    end
    
    return username, password
end

-- ------------------------------------------------------------------
-- Fetch stack URL (Redis cache + auth microservice)
-- ------------------------------------------------------------------
--- @param username string|nil
--- @param auth_service_host string
--- @return string|nil
local function get_stack_url(username, auth_service_host)
    ngx.log(ngx.INFO, "get_stack_url called with username: ", username or "NIL")
    
    if not username then
        ngx.log(ngx.WARN, "Username is nil, cannot proceed")
        return nil
    end

    -- Redis cache
    local red = get_redis()
    if not red then
        ngx.log(ngx.ERR, "Failed to get Redis connection")
        return nil
    end

    local cache_key = "username:" .. username
    ngx.log(ngx.INFO, "Checking Redis cache with key: ", cache_key)
    
    local stack_host, err = red:hget(cache_key, "stack_host")

    if stack_host and stack_host ~= ngx.null then
        ngx.log(ngx.INFO, "User '", username, "' found in cache. Stack host: ", stack_host)
        redis_keepalive(red)
        return stack_host
    else
        ngx.log(ngx.INFO, "User '", username, "' NOT found in cache")
    end

    -- Call auth microservice
    if not auth_service_host then
        ngx.log(ngx.ERR, "No authentication microservice host configured")
        redis_keepalive(red)
        return nil
    end

    local httpc = http.new()
    httpc:set_timeout(2000)

    local request_url = string.format(
        "http://%s/api/users/%s",
        auth_service_host,
        username
    )

    ngx.log(ngx.INFO, "Calling auth service at: ", request_url)

    local res, err = httpc:request_uri(request_url, {
        method = "GET"
    })

    if not res then
        ngx.log(ngx.ERR, "Auth service request failed: ", err)
        redis_keepalive(red)
        return nil
    end

    ngx.log(ngx.INFO, "Auth service response status: ", res.status)
    ngx.log(ngx.INFO, "Auth service response body: ", res.body)

    if res.status == 200 then
        local decoded_body, err = cjson.decode(res.body)
        if not decoded_body then
            ngx.log(ngx.ERR, "JSON decode failed: ", err)
            redis_keepalive(red)
            return nil
        end

        ngx.log(ngx.INFO, "Decoded JSON body: ", cjson.encode(decoded_body))
        
        stack_host = decoded_body
        ngx.log(ngx.INFO, "Setting cache for user '", username, "' with stack_host: ", stack_host)
        
        red:hset(cache_key, "stack_host", stack_host)
        redis_keepalive(red)
        return stack_host
    else
        ngx.log(ngx.WARN, "Auth service returned non-200 status: ", res.status)
    end

    redis_keepalive(red)
    return nil
end

-- ------------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------------
--- @param auth_service_host string
--- @return string|nil
function _M.stack_url_from_authorization(auth_service_host)
    ngx.log(ngx.INFO, "=== stack_url_from_authorization called ===")
    ngx.log(ngx.INFO, "Auth service host: ", auth_service_host)
    
    local username = decode_authorization()
    ngx.log(ngx.INFO, "Username from authorization: ", username or "NIL")
    
    local stack_url = get_stack_url(username, auth_service_host)
    ngx.log(ngx.INFO, "Stack URL result: ", stack_url or "NIL")

    if stack_url then
        ngx.log(ngx.INFO, "Successfully retrieved stack_url: ", stack_url)
        return stack_url
    end

    ngx.log(ngx.WARN, "Authentication failed - returning 401")
    
    -- On error, emulate wazo-auth unauthorized error
    local error_msg = {
        reason = { "Authentication Failed" },
        timestamp = { ngx.now() },
        status_code = 401
    }

    ngx.status = ngx.HTTP_UNAUTHORIZED
    ngx.header.content_type = "application/json"
    ngx.say(cjson.encode(error_msg))
    return ngx.exit(ngx.HTTP_UNAUTHORIZED)
end

--- @param auth_service_host string
--- @return string|nil
function _M.stack_url_from_query(auth_service_host)
    ngx.log(ngx.INFO, "=== stack_url_from_query called ===")
    
    local username =
        ngx.var.arg_email
        or ngx.var.arg_username
        or ngx.var.arg_login

    ngx.log(ngx.INFO, "Username from query: ", username or "NIL")

    local stack_url = get_stack_url(username, auth_service_host)
    if stack_url then
        ngx.log(ngx.INFO, "Successfully retrieved stack_url: ", stack_url)
        return stack_url
    end

    ngx.log(ngx.INFO, "No stack_url found - returning 204")

    ngx.header.access_control_allow_origin = ngx.var.http_origin
    ngx.header.content_type = "application/json"
    ngx.header.vary = "Origin"
    ngx.header.x_powered_by = "wazo-auth"

    return ngx.exit(ngx.HTTP_NO_CONTENT)
end

return _M