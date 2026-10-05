require "fileutils"

namespace :openmarket do
  release = "https://github.com/fireho/openmarket/releases/latest/download/openmarket.ndjson.gz"

  # A path as given, or a URL fetched into tmp/ first.
  def openmarket_file(given, default_url: nil)
    given = given.presence || default_url
    abort "FILE=path|url is needed" unless given
    return given unless given.start_with?("http")

    FileUtils.mkdir_p("tmp")
    dest = File.join("tmp", File.basename(URI(given).path))
    puts "Downloading #{given} -> #{dest}"
    Openmarket::Download.fetch(given, dest)
  end

  def openmarket_counts(stats) = stats.sort.map { |key, n| "#{key} #{n}" }.join(", ")

  def openmarket_progress(label) = ->(stats) { warn "#{label}: #{openmarket_counts(stats)}" }

  def openmarket_indexes
    ::Brand.create_indexes
    ::Product.create_indexes
  end

  desc "Write the shared catalogue as NDJSON. FILE=tmp/openmarket.ndjson.gz"
  task dump: :environment do
    path = ENV.fetch("FILE", "tmp/openmarket.ndjson.gz")
    FileUtils.mkdir_p(File.dirname(path))
    puts "Wrote #{Openmarket::Catalogue.dump(path)} records to #{path}"
  end

  desc "Load a dump into the shared catalogue. FILE=path|url (default: the latest GitHub release) OVERWRITE=1 to replace rows already there"
  task restore: :environment do
    path = openmarket_file(ENV["FILE"], default_url: release)
    openmarket_indexes
    stats = Openmarket::Catalogue.restore(path, overwrite: ENV["OVERWRITE"].present?, progress: openmarket_progress("restore"))
    puts "Done: #{openmarket_counts(stats)}"
  end

  namespace :import do
    desc "Import drinks from Open Food Facts. FILE=path|url (default: their jsonl.gz, several GB) COUNTRIES=en:brazil,en:argentina LIMIT=1000"
    task off: :environment do
      path = openmarket_file(ENV["FILE"], default_url: Openmarket::OpenFoodFacts::DUMP_URL)
      countries = ENV["COUNTRIES"].to_s.split(",").map(&:strip).reject(&:empty?).presence
      limit = ENV["LIMIT"].presence&.to_i

      openmarket_indexes
      importer = Openmarket::Importer.new(progress: openmarket_progress("off"))
      importer.call(Openmarket::OpenFoodFacts.each(path, countries: countries, limit: limit))

      puts "Done: #{openmarket_counts(importer.stats)}"
      importer.errors.first(10).each { |error| warn "  invalid #{error}" }
    end
  end
end
