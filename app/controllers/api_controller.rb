class ApiController < ApplicationController
  protect_from_forgery with: :null_session

  def evaluate_bias
    content = params[:content]
    url = params[:url]

    return render json: { error: "Content is required" }, status: :bad_request if content.blank?
    return render json: { error: "URL is required" }, status: :bad_request if url.blank?

    # Check API call rate limit (50 per day per IP)
    if api_rate_limit_exceeded?
      reset_time = Date.current.end_of_day.to_i
      
      response.headers["X-RateLimit-Limit"] = "1"
      response.headers["X-RateLimit-Remaining"] = "0"
      response.headers["X-RateLimit-Reset"] = reset_time.to_s
      response.headers["Retry-After"] = time_until_reset.to_s
      
      return render json: {
        error: "API rate limit exceeded",
        message: "You have exceeded the daily limit for API calls. Cached results are still available.",
        retry_after_seconds: time_until_reset,
        status: "rate_limited"
      }, status: 429
    end

    begin
      bias_analysis, was_cached = GroqService.analyze_bias_with_cache_tracking(content, url)

      # Only increment rate limit if we made an actual API call
      increment_api_rate_limit unless was_cached

      # Add rate limit headers
      add_rate_limit_headers(was_cached)

      render json: {
        analysis: bias_analysis,
        original_content: content,
        source_url: url,
        timestamp: Time.current,
        status: "success",
        cached: was_cached
      }
    rescue => e
      render json: {
        error: "Analysis failed: #{e.message}",
        timestamp: Time.current,
        status: "error"
      }, status: :internal_server_error
    end
  end

  private

  def client_identifier
    request.remote_ip
  end

  def api_rate_limit_key
    "api_calls:#{client_identifier}:#{Date.current}"
  end

  def api_rate_limit_exceeded?
    current_count = Rails.cache.read(api_rate_limit_key) || 0
    current_count >= 50
  end

  def increment_api_rate_limit
    key = api_rate_limit_key
    current_count = Rails.cache.read(key) || 0
    Rails.cache.write(key, current_count + 1, expires_in: 1.day)
  end

  def current_api_calls
    Rails.cache.read(api_rate_limit_key) || 0
  end

  def time_until_reset
    end_of_day = Date.current.end_of_day
    (end_of_day - Time.current).to_i
  end

  def add_rate_limit_headers(was_cached)
    current_count = current_api_calls
    response.headers["X-RateLimit-Limit"] = "50"
    response.headers["X-RateLimit-Remaining"] = [ 50 - current_count, 0 ].max.to_s
    response.headers["X-RateLimit-Reset"] = Date.current.end_of_day.to_i.to_s
    response.headers["X-Cache-Hit"] = was_cached.to_s
  end
end
