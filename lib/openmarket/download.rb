require "net/http"
require "uri"

module Openmarket
  # A file from a URL onto disk, streamed — the dumps are too big to hold.
  # Follows redirects: a GitHub release asset lives behind one.
  module Download
    def self.fetch(url, dest, redirects: 5)
      uri = URI(url)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request_get(uri) do |response|
          case response
          when Net::HTTPSuccess
            File.open(dest, "wb") { |file| response.read_body { |chunk| file.write(chunk) } }
          when Net::HTTPRedirection
            raise "#{url}: too many redirects" if redirects.zero?
            return fetch(URI.join(url, response["location"]).to_s, dest, redirects: redirects - 1)
          else
            raise "#{url}: #{response.code} #{response.message}"
          end
        end
      end
      dest
    end
  end
end
