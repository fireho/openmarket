module Openmarket
  # Barcodes, spelled however the scanner — or the person — spelled them.
  #
  # One product has one canonical code: a UPC-A (12) is the EAN-13 with a
  # leading zero, a GTIN-14 with a zero indicator is the EAN-13 inside it. An
  # EAN-8 stays itself. Anything that fails its check digit is not a barcode.
  module Ean
    LENGTHS = [ 8, 12, 13, 14 ].freeze

    # "7 891991 010023", "7891991010023" => "7891991010023". nil unless a GTIN.
    def self.normalize(code)
      digits = code.to_s.strip.delete(" -")
      return unless digits.match?(/\A\d+\z/) && LENGTHS.include?(digits.size)
      return unless check_digit(digits[0...-1]) == digits[-1].to_i

      case digits.size
      when 12 then "0#{digits}"
      when 14 then digits.start_with?("0") ? digits[1..] : digits
      else digits
      end
    end

    def self.valid?(code) = !normalize(code).nil?

    # The digit that closes a code: weights 3, 1, 3, 1... from the right.
    def self.check_digit(body)
      sum = body.reverse.each_char.with_index.sum { |c, i| c.to_i * (i.even? ? 3 : 1) }
      (10 - sum % 10) % 10
    end

    # Every spelling a row might have been stored under — old rows keep the
    # code as it was typed, so a lookup asks for all of them.
    def self.variants(code)
      ean = normalize(code) or return []
      return [ ean ] unless ean.size == 13

      [ ean, "0#{ean}", (ean[1..] if ean.start_with?("0")) ].compact
    end
  end
end
