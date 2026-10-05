require "standalone_helper"
require "stringio"
require "tmpdir"

RSpec.describe Openmarket::Dump do
  let(:records) do
    [
      { "type" => "brand", "name" => "Brahma", "info" => nil },
      { "type" => "drink", "code" => "7891991010023", "name" => { "pt" => "Cerveja Brahma é boa" },
        "tags" => [], "acl" => 0.0, "size" => 350 }
    ]
  end

  it "writes a header, then a line per record" do
    io = StringIO.new
    expect(described_class.write(io, records)).to eq(2)

    lines = io.string.lines.map { |line| JSON.parse(line) }
    expect(lines.first).to include("openmarket" => 1, "license" => "ODbL-1.0")
    expect(lines.size).to eq(3)
  end

  it "leaves out what is empty, keeps a real zero" do
    io = StringIO.new
    described_class.write(io, records)

    expect(JSON.parse(io.string.lines[1])).to eq("type" => "brand", "name" => "Brahma")
    expect(JSON.parse(io.string.lines[2])).to eq(records[1].except("tags"))
  end

  it "reads back what it wrote, accents and all" do
    path = File.join(Dir.mktmpdir, "dump.ndjson.gz")
    described_class.write(path, records)

    got = []
    header = described_class.read(path) { |record| got << record }

    expect(header["openmarket"]).to eq(1)
    expect(got).to eq(records.map { |record| described_class.slim(record) })
  end

  it "writes the same bytes for the same records" do
    dir = Dir.mktmpdir
    described_class.write(File.join(dir, "a.ndjson.gz"), records)
    described_class.write(File.join(dir, "b.ndjson.gz"), records)

    expect(File.binread(File.join(dir, "a.ndjson.gz"))).to eq(File.binread(File.join(dir, "b.ndjson.gz")))
  end

  it "reads plain ndjson as well as gzip" do
    path = File.join(Dir.mktmpdir, "dump.ndjson")
    described_class.write(path, records)

    expect(described_class.read(path) { }).to include("openmarket" => 1)
    expect(File.read(path).lines.size).to eq(3)
  end

  it "leaves no dump behind when writing fails halfway" do
    path = File.join(Dir.mktmpdir, "dump.ndjson.gz")
    failing = Enumerator.new do |out|
      out << records.first
      raise "cursor lost"
    end

    expect { described_class.write(path, failing) }.to raise_error("cursor lost")
    expect(Dir.children(File.dirname(path))).to be_empty
  end

  it "keeps the last good dump when the next one fails" do
    path = File.join(Dir.mktmpdir, "dump.ndjson")
    described_class.write(path, records)
    expect { described_class.write(path, Enumerator.new { raise "boom" }) }.to raise_error("boom")

    expect(File.read(path).lines.size).to eq(3)
  end

  it "reads UTF-8 whatever the shell's locale" do
    path = File.join(Dir.mktmpdir, "dump.ndjson")
    described_class.write(path, records)
    external = Encoding.default_external
    Encoding.default_external = Encoding::US_ASCII

    got = []
    described_class.read(path) { |record| got << record }
    expect(got.last["name"]).to eq("pt" => "Cerveja Brahma é boa")
  ensure
    Encoding.default_external = external
  end

  it "refuses what is not a dump" do
    expect { described_class.read(StringIO.new(%({"a":1}\n))) { } }.to raise_error(described_class::Error, /not an openmarket dump/)
    expect { described_class.read(StringIO.new("")) { } }.to raise_error(described_class::Error, /empty/)
  end

  it "refuses a dump from the future" do
    io = StringIO.new(%({"openmarket":99}\n))
    expect { described_class.read(io) { } }.to raise_error(described_class::Error, /newer/)
  end
end
