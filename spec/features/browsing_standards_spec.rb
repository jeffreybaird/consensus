# frozen_string_literal: true

require "spec_helper"

# End to end, through the pages a user actually clicks: save a scan, read it,
# then follow the navigation to the catalog and find the paper behind one of
# the readings. Every clinical value compared here is read from BIOMETRY.catalog
# inside the scenario.
RSpec.feature "Browsing the standards catalog", type: :feature do
  def catalog = BIOMETRY.catalog

  def growth_standard(id) = catalog.growth_standards.find { |standard| standard.id == id }

  def collapsed(text) = text.gsub(/\s+/, " ").strip

  scenario "a user follows the navigation from a saved scan to the catalog" do
    scan = create(:scan)

    visit "/scans/#{scan.id}"
    find('a[href="/standards"]').click

    expect(page).to have_current_path("/standards")
    expect(page).to have_css('[data-testid="growth-standards"]')
    expect(page).to have_css('[data-testid="efw-formulas"]')
    expect(page).to have_css('[data-testid="dating-methods"]')
    expect(page).to have_css('[data-testid="redating-policy"]')
  end

  scenario "a user reads the paper behind a standard they saw on a scan" do
    create(:scan)
    standard = growth_standard(:intergrowth21)

    visit "/standards"
    entry = find(%([data-testid="standard-#{standard.id}"]), visible: :all)

    expect(collapsed(entry.text(:all))).to include(collapsed(standard.citation))
    expect(entry.all("a", visible: :all).map { |link| link[:href] })
      .to include("https://doi.org/#{standard.doi}")
  end

  scenario "a user finds out why the two Hadlock readings disagree" do
    issue = growth_standard(:hadlock_1991_equation)
            .known_issues.find { |known| known[:id].to_s.include?("dispersion") }

    visit "/standards"

    %i[hadlock_1991_equation hadlock_1991_table].each do |id|
      entry = find(%([data-testid="standard-#{id}"]), visible: :all)

      expect(collapsed(entry.text(:all))).to include(collapsed(issue[:detail].split(". ").first))
    end
  end

  scenario "the catalog page labels nothing" do
    visit "/standards"

    expect(page.body).not_to match(/\b(SGA|LGA|IUGR|FGR|macrosomia|abnormal)\b/i)
  end
end
