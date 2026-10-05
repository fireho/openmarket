require "standalone_helper"

RSpec.describe Openmarket::Ean do
  describe ".normalize" do
    it "keeps a good EAN-13" do
      expect(described_class.normalize("4006381333931")).to eq("4006381333931")
    end

    it "makes a UPC-A the EAN-13 it is inside of" do
      expect(described_class.normalize("036000291452")).to eq("0036000291452")
    end

    it "keeps an EAN-8" do
      expect(described_class.normalize("96385074")).to eq("96385074")
    end

    it "unwraps a GTIN-14 with a zero indicator, keeps one with a real indicator" do
      expect(described_class.normalize("04006381333931")).to eq("4006381333931")
      expect(described_class.normalize("14006381333938")).to eq("14006381333938")
    end

    it "takes the spaces and dashes a person types" do
      expect(described_class.normalize(" 4 006381 333931 ")).to eq("4006381333931")
      expect(described_class.normalize("4006381-333931")).to eq("4006381333931")
    end

    it "refuses a wrong check digit" do
      expect(described_class.normalize("4006381333932")).to be_nil
    end

    it "refuses what is not a barcode at all" do
      expect(described_class.normalize("")).to be_nil
      expect(described_class.normalize(nil)).to be_nil
      expect(described_class.normalize("123456")).to be_nil
      expect(described_class.normalize("abc4006381333931")).to be_nil
    end
  end

  describe ".valid?" do
    it { expect(described_class.valid?("5901234123457")).to be true }
    it { expect(described_class.valid?("5901234123458")).to be false }
  end

  describe ".variants" do
    it "lists every spelling an old row may be stored under" do
      expect(described_class.variants("036000291452")).to eq(%w[ 0036000291452 00036000291452 036000291452 ])
    end

    it "has just the EAN-13 when no other spelling exists" do
      expect(described_class.variants("4006381333931")).to eq(%w[ 4006381333931 04006381333931 ])
    end

    it "is empty for a non-barcode" do
      expect(described_class.variants("sku-9")).to eq([])
    end
  end
end

RSpec.describe Openmarket::Text do
  it "folds case, accents and spaces" do
    expect(described_class.fold("  Antártica   Original ")).to eq("antartica original")
    expect(described_class.fold("ANTÁRTICA")).to eq(described_class.fold("antartica"))
  end

  it "folds nothing to nothing" do
    expect(described_class.fold(nil)).to eq("")
  end
end
