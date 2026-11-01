target :gen do
	check "examples"
	signature "examples"

	# stdlib signatures for the types the generated code refers to (BigDecimal, Date, Time, IPAddr, Set, Tempfile; CSV has no useful signature)
	library "bigdecimal", "date", "time", "ipaddr", "set", "tempfile"
end
