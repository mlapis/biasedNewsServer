class Rack::Attack
  # Cache store for rate limiting data
  Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

  # Safeguard throttle - absolute limit to prevent abuse
  throttle("api/absolute-limit", limit: 200, period: 1.day) do |req|
    if req.path == "/api/evaluate_bias" && req.post?
      req.ip
    end
  end

  # Custom response for rate limited requests
  self.throttled_responder = lambda do |request|
    match_data = request.env['rack.attack.match_data']
    now = match_data[:epoch_time]

    headers = {
      "Content-Type" => "application/json",
      "X-RateLimit-Limit" => match_data[:limit].to_s,
      "X-RateLimit-Remaining" => "0",
      "X-RateLimit-Reset" => (now + match_data[:period]).to_s,
      "Retry-After" => match_data[:period].to_s
    }

    body = {
      error: "Rate limit exceeded",
      message: "Too many requests. Please try again later.",
      retry_after_seconds: match_data[:period],
      status: "rate_limited"
    }.to_json

    [ 429, headers, [ body ] ]
  end
end
