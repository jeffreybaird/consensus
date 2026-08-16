# frozen_string_literal: true

require "spec_helper"

# The catalog page. Every value asserted here is read out of BIOMETRY.catalog
# inside the example — a standard, formula, window, citation or known issue
# added to or changed in the gem must show up on this page without this file
# changing. Nothing clinical is typed.
RSpec.describe "Standards", type: :request do
  def rendered = Capybara.string(last_response.body)

  def catalog = BIOMETRY.catalog

  def entry(id) = rendered.find(%([data-testid="standard-#{id}"]), visible: :all)

  def formula_entry(id) = rendered.find(%([data-testid="formula-#{id}"]), visible: :all)

  def section(id) = rendered.find(%([data-testid="#{id}"]), visible: :all)

  # Details elements are collapsed by default; the disclosed text is what the
  # page carries, so read it whether or not it is open.
  def disclosed(node) = node.text(:all)

  def collapsed(text) = text.gsub(/\s+/, " ").strip

  def first_sentence(text) = text.split(". ").first

  def growth_standard(id) = catalog.growth_standards.find { |standard| standard.id == id }

  describe "GET /standards" do
    before { get "/standards" }

    it "responds ok" do
      expect(last_response).to be_ok
    end

    describe "the growth standards section" do
      it "is on the page" do
        expect(rendered.all('[data-testid="growth-standards"]', visible: :all).size).to eq(1)
      end

      it "renders one entry per growth standard the catalog serves" do
        ids = section("growth-standards").all('[data-testid^="standard-"]', visible: :all)
                                         .map { |node| node[:"data-testid"] }

        expect(ids).to match_array(catalog.growth_standards.map { |s| "standard-#{s.id}" })
      end

      it "names every standard" do
        catalog.growth_standards.each do |standard|
          expect(disclosed(entry(standard.id))).to include(Standards::Names.standard(standard.id))
        end
      end

      it "cites every standard's paper" do
        catalog.growth_standards.each do |standard|
          expect(collapsed(disclosed(entry(standard.id)))).to include(collapsed(standard.citation))
        end
      end

      it "gives every standard's gestation window" do
        catalog.growth_standards.each do |standard|
          text = disclosed(entry(standard.id))
          from, to = standard.valid_ga_weeks

          expect(text).to include(from.to_s).and include(to.to_s)
        end
      end

      it "says what kind of standard each one is" do
        catalog.growth_standards.each do |standard|
          expect(disclosed(entry(standard.id))).to match(/#{standard.type}/i)
        end
      end

      it "links the DOI of every standard that has one" do
        cited = catalog.growth_standards.reject { |standard| standard.doi.nil? }

        expect(cited).not_to be_empty
        cited.each do |standard|
          links = entry(standard.id).all("a", visible: :all).map { |a| a[:href] }

          expect(links).to include("https://doi.org/#{standard.doi}")
        end
      end

      it "links INTERGROWTH-21st's DOI as the catalog publishes it" do
        standard = growth_standard(:intergrowth21)

        expect(standard.doi).not_to be_nil
        expect(entry(:intergrowth21).all("a", visible: :all).map { |a| a[:href] })
          .to include("https://doi.org/#{standard.doi}")
      end

      it "shows the PMID of every standard that has one" do
        cited = catalog.growth_standards.reject { |standard| standard.pmid.nil? }

        expect(cited).not_to be_empty
        cited.each do |standard|
          expect(disclosed(entry(standard.id))).to include(standard.pmid)
        end
      end

      it "shows both Hadlock readings' PMID" do
        %i[hadlock_1991_equation hadlock_1991_table].each do |id|
          pmid = growth_standard(id).pmid

          expect(pmid).not_to be_nil
          expect(disclosed(entry(id))).to include(pmid)
        end
      end

      it "carries the known issues of every standard that has any" do
        flagged = catalog.growth_standards.reject { |standard| standard.known_issues.to_a.empty? }

        expect(flagged).not_to be_empty
        flagged.each do |standard|
          text = collapsed(disclosed(entry(standard.id)))

          standard.known_issues.each do |issue|
            expect(text).to include(collapsed(first_sentence(issue[:detail])))
          end
        end
      end

      it "discloses the contested Hadlock dispersion, in the catalog's own words" do
        %i[hadlock_1991_equation hadlock_1991_table].each do |id|
          issue = growth_standard(id).known_issues
                                     .find { |known| known[:id].to_s.include?("dispersion") }

          expect(issue).not_to be_nil
          expect(collapsed(disclosed(entry(id))))
            .to include(collapsed(first_sentence(issue[:detail])))
        end
      end
    end

    describe "the weight formulas section" do
      it "is on the page" do
        expect(rendered.all('[data-testid="efw-formulas"]', visible: :all).size).to eq(1)
      end

      it "renders one entry per formula the catalog serves" do
        ids = section("efw-formulas").all('[data-testid^="formula-"]', visible: :all)
                                     .map { |node| node[:"data-testid"] }

        expect(ids).to match_array(catalog.efw_formulas.map { |f| "formula-#{f.id}" })
      end

      # Read from the entry's own "requires" element, not from the whole entry:
      # the equation prints AC, FL and BPD too, so an entry-wide assertion would
      # pass on a page that never listed what the formula needs.
      it "names the measurements each formula is read from, in the sonographer's notation" do
        catalog.efw_formulas.each do |formula|
          node = rendered.find(%([data-testid="formula-#{formula.id}-requires"]), visible: :all)

          formula.requires.each { |kind| expect(node.text(:all)).to include(kind.to_s.upcase) }
        end
      end

      it "prints every formula's equation as its paper prints it" do
        catalog.efw_formulas.each do |formula|
          expect(collapsed(disclosed(formula_entry(formula.id))))
            .to include(collapsed(formula.equation))
        end
      end

      it "prints the INTERGROWTH equation the catalog publishes" do
        formula = catalog.efw_formulas.find { |entry| entry.id == :intergrowth }

        expect(formula).not_to be_nil
        expect(collapsed(disclosed(formula_entry(formula.id))))
          .to include(collapsed(formula.equation))
      end

      it "cites every formula's paper" do
        catalog.efw_formulas.each do |formula|
          expect(collapsed(disclosed(formula_entry(formula.id))))
            .to include(collapsed(formula.citation))
        end
      end
    end

    describe "the dating methods section" do
      it "is on the page" do
        expect(rendered.all('[data-testid="dating-methods"]', visible: :all).size).to eq(1)
      end

      it "cites each dating method the catalog serves exactly once" do
        text = collapsed(disclosed(section("dating-methods")))

        expect(catalog.dating_methods).not_to be_empty
        catalog.dating_methods.each do |method|
          expect(text.scan(collapsed(method.citation)).size).to eq(1)
        end
      end

      it "names the standard each dating method derives from" do
        text = disclosed(section("dating-methods"))

        catalog.dating_methods.each do |method|
          expect(text).to include(Standards::Names.standard(method.standard))
        end
      end
    end

    describe "the redating policy section" do
      it "is on the page" do
        expect(rendered.all('[data-testid="redating-policy"]', visible: :all).size).to eq(1)
      end

      it "cites the policy's paper" do
        expect(collapsed(disclosed(section("redating-policy"))))
          .to include(collapsed(catalog.redating_policy.citation))
      end

      it "carries what the policy admits is unverified about it" do
        issues = catalog.redating_policy.known_issues
        text = collapsed(disclosed(section("redating-policy")))

        expect(issues).not_to be_empty
        issues.each { |issue| expect(text).to include(collapsed(first_sentence(issue[:detail]))) }
      end
    end

    it "never labels a reading" do
      expect(last_response.body).not_to match(/\b(SGA|LGA|IUGR|FGR|macrosomia|abnormal)\b/i)
    end
  end

  describe "GET /" do
    it "links to the standards page" do
      get "/"

      expect(Capybara.string(last_response.body).all('a[href="/standards"]', visible: :all))
        .not_to be_empty
    end
  end
end
