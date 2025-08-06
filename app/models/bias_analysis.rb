class BiasAnalysis < ApplicationRecord
  validates :normalized_url, presence: true, uniqueness: true
  validates :domain, presence: true
  validates :trust_level, presence: true, inclusion: { in: %w[reliable questionable unreliable] }
  validates :analysis_result, presence: true
  validates :api_model, presence: true
end
