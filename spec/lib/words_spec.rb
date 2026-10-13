require "yaml"
require "standalone_helper"

# What a person reads comes from the locales, in en and pt alike: the product
# screens name a key, never a word.
RSpec.describe "the words" do
  root = File.expand_path("../..", __dir__)
  locales = %w[ en pt ].to_h { |lang| [ lang, YAML.load_file("#{root}/config/locales/openmarket.#{lang}.yml")[lang] ] }
  views = Dir["#{root}/app/views/products/*.erb"].to_h { |file| [ File.basename(file), File.read(file, encoding: "UTF-8") ] }

  def self.keys(tree, path = [])
    tree.flat_map { |key, value| value.is_a?(Hash) ? keys(value, path + [ key ]) : [ (path + [ key ]).join(".") ] }
  end

  it "has the same keys in en and pt" do
    expect(self.class.keys(locales["en"]).sort).to eq(self.class.keys(locales["pt"]).sort)
  end

  it "finds every key the product screens name, in en and pt" do
    used = views.values.join.scan(/\bt\("([\w.]+)"/).flatten.uniq
    expect(used).not_to be_empty
    locales.each do |lang, tree|
      missing = used.reject { |key| tree.dig(*key.split(".")) }
      expect(missing).to be_empty, "#{lang} lacks #{missing.join(', ')}"
    end
  end

  it "writes no word straight into a product screen" do
    literal = /(?:link_to|button_to|submit|label\(\s*:\w+,|include_blank:|turbo_confirm:|content_for :title,)\s*"/
    views.each do |name, source|
      expect(source.scan(/.*#{literal}.*/)).to be_empty, "#{name} writes a word in place"
    end
  end

  it "keeps no bare word (a unit like ml is no word) between the tags of a product screen" do
    views.each do |name, source|
      text = source.gsub(/<script>.*?<\/script>/m, "").gsub(/<%.*?%>/m, "").gsub(/<[^>]*>/m, "")
      expect(text.scan(/[[:alpha:]]{3,}/)).to be_empty, "#{name} keeps #{text.split.join(' ')}"
    end
  end
end
