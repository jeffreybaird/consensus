# frozen_string_literal: true

# The template's demo domain. Nothing is deployed yet, so dropping it is safe;
# once something ships, migrations must be additive (.claude/deployment.md).
Sequel.migration do
  up { drop_table(:notes) }
  down do
    create_table(:notes) do
      primary_key :id
      String   :body, text: true, null: false
      DateTime :created_at
      DateTime :updated_at
    end
  end
end
