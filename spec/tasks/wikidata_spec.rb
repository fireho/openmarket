require "rails_helper"
require "rake"

# The task picks the brands to ask about; Wikidata itself is stubbed.
RSpec.describe "openmarket:import:wikidata" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  it "asks Wikidata about shared brands only" do
    Brand.create!(name: "Brahma")
    Brand.create!(name: "Marca do Ze", org_id: Org.create!(name: "A").id)
    asked = []
    allow(Openmarket::Wikidata).to receive(:ask) { |names, _http| asked.concat(names) && [] }

    expect { Rake::Task["openmarket:import:wikidata"].execute }.to output.to_stdout.and output.to_stderr
    expect(asked).to eq([ "Brahma" ])
  end
end
