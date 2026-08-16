# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:notes) do
      primary_key :id
      String   :body, text: true, null: false
      DateTime :created_at
      DateTime :updated_at
    end
  end
end
