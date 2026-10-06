# A host says which money it counts in.
Money.default_currency = Money::Currency.new("BRL")
Money.rounding_mode = BigDecimal::ROUND_HALF_EVEN
Money.locale_backend = :currency
