module Openmarket
  # Barcodes, spelled however the scanner — or the person — spelled them.
  #
  # One product has one canonical code, decided by the GTIN's value, not by how
  # many digits it was written with: a UPC-A (12) is the EAN-13 with a leading
  # zero, a GTIN-14 with a zero indicator is the EAN-13 inside it, an EAN-8
  # padded to 13 or 14 digits is still the EAN-8, and a UPC-E (the short code
  # on a 12oz can) is the UPC-A it compresses. Anything that fails its check
  # digit is not a barcode.
  module Ean
    LENGTHS = [ 8, 12, 13, 14 ].freeze

    # "7 891991 010023", "7891991010023" => "7891991010023". nil unless a GTIN.
    def self.normalize(code)
      digits = digits(code) or return
      return unless LENGTHS.include?(digits.size)

      if digits.size == 8
        # An 8-digit code is an EAN-8 or a UPC-E. EAN-8s starting with 0 are
        # in-store numbers, so there UPC-E is the likelier reading.
        readings = [ upc_e(digits), (digits if check?(digits)) ]
        readings.reverse! unless digits.start_with?("0")
        return readings.compact.first
      end

      return unless check?(digits)

      gtin = digits.rjust(14, "0")
      if gtin.start_with?("000000") then gtin[6..]   # an EAN-8, however padded
      elsif gtin.start_with?("0") then gtin[1..]     # an EAN-13 (or a UPC-A)
      else gtin                                      # a real GTIN-14
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

      # The same number with fewer leading zeros: 14, 13, 12 and 8 digits.
      gtin = ean.rjust(14, "0")
      padded = [ 14, 13, 12, 8 ].filter_map { |n| gtin[-n..] if gtin[0, 14 - n].delete("0").empty? }
      ([ ean ] + padded + [ digits(code) ]).compact.uniq
    end

    # Only the digits a person may put around them: spaces and dashes. A code
    # with letters is a house code, not a barcode.
    def self.digits(code)
      text = code.to_s.strip.delete(" \u00A0-") # the dash last, or it is a range
      text if text.match?(/\A[0-9]+\z/)
    end

    def self.check?(digits) = check_digit(digits[0...-1]) == digits[-1].to_i

    # A UPC-E, expanded to the UPC-A it stands for — as an EAN-13. nil unless
    # it is one: number system 0 or 1, and the UPC-A's check digit agrees.
    def self.upc_e(digits)
      return unless digits.size == 8 && digits.start_with?("0", "1")

      system, d, check = digits[0], digits[1, 6], digits[7]
      body = case d[5]
      when "0", "1", "2" then "#{d[0, 2]}#{d[5]}0000#{d[2, 3]}"
      when "3" then "#{d[0, 3]}00000#{d[3, 2]}"
      when "4" then "#{d[0, 4]}00000#{d[4]}"
      else "#{d[0, 5]}0000#{d[5]}"
      end
      upc_a = "#{system}#{body}#{check}"
      "0#{upc_a}" if check?(upc_a)
    end
  end
end
