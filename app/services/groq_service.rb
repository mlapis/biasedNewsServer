class GroqService
  include HTTParty

  base_uri "https://api.groq.com"

  BIAS_ANALYSIS_PROMPT = <<~PROMPT
    You are an expert bias detection analyst. Analyze content for manipulation techniques with SEVERITY SCORING (0-10).

    **SEVERITY SCALE:**
    0-1: Negligible (standard journalistic choices, minor word choices)
    2-4: Minor (some slant, missing context, weak sourcing)
    5-7: Significant (clear bias, misleading data, emotional manipulation)
    8-10: Critical (propaganda, fabrication, dangerous misinformation)

    **DETECTION CATEGORIES:**
    - emotional_manipulation: Fear/anger language, loaded terms, artificial urgency
    - missing_sources: Unsourced claims, no expert quotes, anonymous sources
    - selective_data: Cherry-picked stats, truncated timeframes, misleading charts
    - authority_misuse: Fake credentials, conflicts of interest, false expertise
    - framing_bias: One-sided narrative, omitted perspectives, selective emphasis
    - social_proof_abuse: Viral manipulation, artificial amplification, bandwagon appeals

    **SEVERITY TRAINING EXAMPLES:**

    SEVERITY 9-10 Examples:
    - "Democrats want to destroy America" (emotional_manipulation) - extreme partisan language
    - "Study shows 90% support" with no study cited (missing_sources) - fabricated statistics

    SEVERITY 6-8 Examples:
    - "Critics slam the controversial decision" (emotional_manipulation) - loaded language
    - "Experts believe" without naming sources (missing_sources) - vague authority

    SEVERITY 3-5 Examples:
    - Using "soar" vs "increase" for same data (framing_bias) - word choice bias
    - Quoting only one side in complex issue (selective_data) - missing perspective

    SEVERITY 0-2 Examples:
    - "The policy aims to reduce costs" (neutral reporting)
    - Standard AP style headlines (professional journalism)

    **TRUST LEVELS:**
    - reliable: Well-sourced, balanced, severity ≤ 4
    - questionable: Some manipulation, severity 5-7#{' '}
    - unreliable: Significant manipulation, severity ≥ 8

    Also extract all author names from bylines/attributions into an authors array.

    Return JSON with this exact structure:
    {
      "trust_level": "reliable|questionable|unreliable",
      "authors": [],
      "detections": [
        {
          "type": "category",
          "label": "specific issue found",
          "description": "concrete example with quote/context",
          "severity": 0-10,
          "example": "direct quote or specific reference"
        }
      ]
    }

    ONLY include detections with severity ≥ 5. Order by severity (highest first). Maximum 3 detections.
    Be SPECIFIC - cite actual quotes, specific claims, concrete examples. Avoid generic pattern-matching.

    The text you are getting is not cleaned. You might have ads, paywalls, other articles and offers included.
    Please ignore those in your analysis completely.

    Article:
  PROMPT

  def self.analyze_bias_with_cache(content, url)
    result, _was_cached = analyze_bias_with_cache_tracking(content, url)
    result
  end

  def self.analyze_bias_with_cache_tracking(content, url)
    normalized_url = normalize_url(url)
    domain = extract_domain(url)

    # Check cache first
    cached_analysis = BiasAnalysis.find_by(normalized_url: normalized_url)
    return [ cached_analysis.analysis_result, true ] if cached_analysis

    # Make API call
    analysis_json = analyze_bias(content)
    analysis_data = JSON.parse(analysis_json)

    # Save to cache
    BiasAnalysis.create!(
      normalized_url: normalized_url,
      domain: domain,
      authors: analysis_data["authors"] || [],
      trust_level: analysis_data["trust_level"],
      analysis_result: analysis_data,
      api_model: "llama3-8b-8192"
    )

    [ analysis_json, false ]
  end

  def self.analyze_bias(content)
    truncated_content = content.split.first(500).join(" ")

    response = post("/openai/v1/chat/completions",
      headers: {
        "Content-Type" => "application/json",
        "Authorization" => "Bearer #{ENV['GROQ_API_KEY']}"
      },
      body: {
        messages: [
          {
            role: "user",
            content: "#{BIAS_ANALYSIS_PROMPT}\n\n#{truncated_content}"
          }
        ],
        model: "llama3-8b-8192",
        temperature: 1,
        max_completion_tokens: 1024,
        top_p: 1,
        stream: false,
        stop: nil,
        response_format: { type: "json_object" }
      }.to_json
    )

    if response.success?
      response.parsed_response.dig("choices", 0, "message", "content")
    else
      Rails.logger.error "Groq API error: #{response.code} #{response.message}"
      Rails.logger.error "Groq API response body: #{response.body}"
      raise "Groq API error: #{response.code} #{response.message} - #{response.body}"
    end
  end

  private

  def self.normalize_url(url)
    uri = URI.parse(url)
    "#{uri.host}#{uri.path}".chomp("/")
  end

  def self.extract_domain(url)
    URI.parse(url).host
  end
end
