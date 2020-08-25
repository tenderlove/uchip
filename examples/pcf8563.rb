require "uchip/mcp2221"

# Example to read from a PCF8563 real time clock
# https://www.nxp.com/docs/en/data-sheet/PCF8563.pdf

# These are just encoding and decoding routines for data on the RTC.

def bcd2dec val
  ((val >> 4) * 10) + (val & 0xF)
end

def dec2bcd val
  ((val / 10) << 4) | (val % 10)
end

def time2bcd time
  [ time.sec,
    time.min,
    time.hour,
    time.day,
    time.wday,
    time.month,
    time.year % 2000
  ].map { |x| dec2bcd(x) }
end

def bcd2time bytes
  seconds, minutes, hours, days, weekdays, c_months, years = bytes
  Time.local bcd2dec(years) + 2000,
             bcd2dec(c_months & 0xF) + 1, # don't care about century flag
             bcd2dec(days & 0x3F),
             bcd2dec(hours & 0x3F),
             bcd2dec(minutes & 0x7F),
             bcd2dec(seconds & 0x7F)
end

# Find the first connected chip
chip = UChip::MCP2221.first || raise("Couldn't find the chip!")

# The write address is 0xA2, read address is 0xA3, so 0x51 (0xA3 >> 1) is
# where we'll request a proxy
i2c  = chip.i2c_on 0x51

# Reset the I2C engine. I've noticed sometimes the engine gets messed up, so
# just start off by putting it in a known state.
i2c.cancel

# Write the current time to the RTC, starting at address 0x2
i2c.write 0x2.chr + time2bcd(Time.now).pack("C7")

loop do
  # Write 0 bytes at address 0x2. This moves the pointer to the seconds location
  # inside the RTC.
  i2c.write 0x2.chr

  # Read 7 bytes
  buf = i2c.read 7
  p bcd2time(buf.bytes)
  sleep 1
rescue UChip::MCP2221::EmptyResponse
  # if the chip gets messed up, reset the i2c engine and retry
  puts "oh no"
  i2c.cancel
  retry
end
