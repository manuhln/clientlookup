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

    local ok, err = red:connect("redis", 6379)
    if not ok then
        ngx.log(ngx.ERR, "Redis connection failed: ", err)
        return nil
    end

    return red
end

local function redis_keepalive(red)
    if not red then
        return
    end

    local ok, err = red:set_keepalive(10_000, 100)
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
    if not authorization then
        return nil
    end

    local prefix = "Basic "
    if authorization:sub(1, #prefix) ~= prefix then
        return nil
    end

    local encoded = authorization:sub(#prefix + 1)
    local decoded = ngx.decode_base64(encoded)
    if not decoded then
        return nil
    end

    local username, password = decoded:match("^([^:]+):(.+)$")
    return username, password
end

-- ------------------------------------------------------------------
-- Fetch stack URL (Redis cache + auth microservice)
-- ------------------------------------------------------------------
--- @param username string|nil
--- @param auth_service_host string
--- @return string|nil
local function get_stack_url(username, auth_service_host)
    if not username then
        goto error_exit
    end

    -- Redis cache
    local red = get_redis()
    if not red then
        goto error_exit
    end

    local cache_key = "user:" .. username
    local stack_host, err = red:hget(cache_key, "stack_host")

    if stack_host and stack_host ~= ngx.null then
        ngx.log(ngx.INFO, "User '", username, "' found in cache")
        redis_keepalive(red)
        return stack_host
    end

    -- Call auth microservice
    if not auth_service_host then
        ngx.log(ngx.ERR, "No authentication microservice host configured")
        redis_keepalive(red)
        goto error_exit
    end

    local httpc = http.new()
    httpc:set_timeout(2000)

    local request_url = string.format(
        "http://%s/users/%s",
        auth_service_host,
        username
    )

    local res, err = httpc:request_uri(request_url, {
        method = "GET"
    })

    if not res then
        ngx.log(ngx.ERR, "Auth service request failed: ", err)
        redis_keepalive(red)
        goto error_exit
    end

    if res.status == 200 then
        local decoded_body, err = cjson.decode(res.body)
        if not decoded_body then
            ngx.log(ngx.ERR, "JSON decode failed: ", err)
            redis_keepalive(red)
            goto error_exit
        end

        stack_host = decoded_body
        red:hset(cache_key, "stack_host", stack_host)
        redis_keepalive(red)
        return stack_host
    end

    redis_keepalive(red)

::error_exit::
    return nil
end

-- ------------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------------
--- @param auth_service_host string
--- @return string|nil
function _M.stack_url_from_authorization(auth_service_host)
    local username = decode_authorization()
    local stack_url = get_stack_url(username, auth_service_host)

    if stack_url then
        return stack_url
    end

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
    local username =
        ngx.var.arg_email
        or ngx.var.arg_username
        or ngx.var.arg_login

    local stack_url = get_stack_url(username, auth_service_host)
    if stack_url then
        return stack_url
    end

    ngx.header.access_control_allow_origin = ngx.var.http_origin
    ngx.header.content_type = "application/json"
    ngx.header.vary = "Origin"
    ngx.header.x_powered_by = "wazo-auth"

    return ngx.exit(ngx.HTTP_NO_CONTENT)
end

return _M
