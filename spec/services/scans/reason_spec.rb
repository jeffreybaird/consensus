# frozen_string_literal: true

require "spec_helper"

RSpec.describe Scans::Reason do
  # The failure tuples below are hand-built shapes, not clinical facts: the
  # numbers in them are payload values this formatter must repeat back, and
  # the assertions only ever look for what the payload already carried.
  def sentence(tag, payload = nil)
    described_class.call(payload.nil? ? [tag] : [tag, payload])
  end

  describe ".call" do
    context "when the gestation is outside the standard's window" do
      let(:payload) { { standard: :nichd, ga_weeks: 13.285714285714286, valid_range: [15, 40] } }
      let(:result) { sentence(:out_of_range, payload) }

      it "names the standard that refused" do
        expect(result).to match(/nichd/i)
      end

      it "names the window that standard covers" do
        expect(result).to include("15").and include("40")
      end

      it "names the gestation it was asked about" do
        expect(result).to include("13")
      end

      it "invents no window of its own" do
        other = sentence(:out_of_range, payload.merge(valid_range: [22, 40]))

        expect(other).to include("22")
        expect(other).not_to include("15")
      end
    end

    context "when a measurement the formula needs was not recorded" do
      let(:result) { sentence(:insufficient_data, { required: %i[bpd hc ac fl], given: [:bpd] }) }

      it "names every measurement the formula requires, in upper case" do
        expect(result).to include("BPD").and include("HC").and include("AC").and include("FL")
      end

      it "says which of them this scan is missing" do
        # A missing measurement is named both as required and as missing; one
        # that was recorded is only named as required. An implementation that
        # reports the required list as the missing list fails this.
        expect(result.scan("FL").size).to be > result.scan("BPD").size
      end

      it "names only the measurements in this payload" do
        other = sentence(:insufficient_data, { required: %i[ac hc], given: [] })

        expect(other).to include("AC").and include("HC")
        expect(other).not_to include("FL")
      end
    end

    context "when a formula and a chart do not pair" do
      let(:result) do
        sentence(:formula_chart_mismatch,
                 { chart: :who, expected: :hadlock_hc_ac_fl, given: :intergrowth })
      end

      it "names the chart" do
        expect(result).to match(/who/i)
      end

      it "names the formula the chart expects and the one it was given" do
        expect(result).to match(/hadlock/i).and match(/intergrowth/i)
      end
    end

    context "when the input was invalid" do
      let(:result) { sentence(:invalid_input, { ga: ["is not present"] }) }

      it "names the field that could not be read" do
        expect(result).to include("ga")
      end

      it "repeats what was wrong with it" do
        expect(result).to include("is not present")
      end
    end

    context "when the centile asked for is not one the standard publishes" do
      let(:result) do
        sentence(:unsupported_centile,
                 { standard: :who, requested: 2.5, available: [5, 10, 25, 50, 75, 90, 95] })
      end

      it "names the standard" do
        expect(result).to match(/WHO/)
      end

      it "lists the centiles that standard does publish" do
        [5, 10, 25, 50, 75, 90, 95].each { |centile| expect(result).to include(centile.to_s) }
      end

      it "names the centile that was asked for" do
        expect(result).to include("2.5")
      end
    end

    context "when no chart is served under the name asked for" do
      let(:result) do
        sentence(:unsupported_standard, { requested: :banana, available: %i[intergrowth21 who] })
      end

      it "names what was asked for" do
        expect(result).to include("banana")
      end

      it "names what is on offer, by display name rather than by id" do
        expect(result).to include("INTERGROWTH-21st").and include("WHO")
        expect(result).not_to include("intergrowth21")
      end
    end

    context "with a tag this app has no wording for" do
      it "handles a tag it has never seen" do
        expect { sentence(:kaboom_frobnicator, {}) }.not_to raise_error
        expect(sentence(:kaboom_frobnicator, {})).to match(/kaboom frobnicator/i)
      end

      it "handles a failure carrying no payload at all" do
        expect { sentence(:not_found) }.not_to raise_error
        expect(sentence(:not_found)).to match(/not found/i)
      end
    end

    describe "the wording itself" do
      failures = {
        out_of_range: { standard: :who, ga_weeks: 10, valid_range: [14, 40] },
        insufficient_data: { required: %i[hc ac fl], given: [:bpd] },
        formula_chart_mismatch: { chart: :nichd, expected: :hadlock_hc_ac_fl, given: :intergrowth },
        invalid_input: { ga: ["is not present"] },
        unsupported_standard: { requested: :crl, available: %i[lmp transfer] },
        unsupported_centile: { standard: :nichd, requested: 2.5, available: [5, 50, 95] }
      }

      failures.each do |tag, payload|
        context "for #{tag}" do
          let(:result) { sentence(tag, payload) }

          it "reads as a sentence" do
            expect(result).to match(/\A[A-Z].*\.\z/m)
          end

          it "shows no raw tag" do
            expect(result).not_to include(tag.to_s)
          end
        end
      end
    end
  end
end
