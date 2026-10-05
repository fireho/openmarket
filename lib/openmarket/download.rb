require "net/http"
require "uri"

module Openmarket
  # A file from a URL onto disk, streamed — the dumps are too big to hold.
  # Follows redirects (a GitHub release asset lives behind one), but never from
  # https down to http. The file lands whole or not at all: it is written beside
  # `dest` and moved into place when the last byte is in.
  module Download
    def self.fetch(url, dest, redirects: 5)
      uri = URI(url)
      partial = "#{dest}.partial"
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request_get(uri) do |response|
          case response
          when Net::HTTPSuccess
            File.open(partial, "wb") { |file| response.read_body { |chunk| file.write(chunk) } }
            File.rename(partial, dest)
          when Net::HTTPRedirection
            raise "#{url}: too many redirects" if redirects.zero?

            target = URI.join(url, response["location"])
            raise "#{url}: refusing to follow a redirect to #{target.scheme}" if uri.scheme == "https" && target.scheme != "https"
            return fetch(target.to_s, dest, redirects: redirects - 1)
          else
            raise "#{url}: #{response.code} #{response.message}"
          end
        end
      end
      dest
    ensure
      File.delete(partial) if partial && File.exist?(partial)
    end
  end
end
