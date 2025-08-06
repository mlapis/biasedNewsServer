class CreateBiasAnalyses < ActiveRecord::Migration[8.0]
  def change
    create_table :bias_analyses do |t|
      t.string :normalized_url
      t.string :domain
      t.json :authors
      t.string :trust_level
      t.json :analysis_result
      t.string :api_model

      t.timestamps
    end
    add_index :bias_analyses, :normalized_url
  end
end
