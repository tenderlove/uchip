# These are just regression tests to make sure stuff works.
# I recorded the interaction between a working test script and the pfc8563
# and this test just ensures that the client reads / writes the same bytes as
# the IRL script did.

require "helper"

class PFC8563Test < UChip::TestCase
  BASE_DIR = File.join File.dirname(__FILE__), "pcf8563"
  Dir.entries(BASE_DIR).each do |f|
    f = File.join BASE_DIR, f
    next unless File.file?(f) && f.end_with?(".yml")

    record = Psych.load_file f
    test_name = f[/\w+(?=.yml)/]
    define_method :"test_#{test_name}" do
      #chip = UChip::MCP2221.new Object.new, record
      chip = make_replay record
      i2c  = chip.i2c_on 0x51
      i2c.cancel
      bytes = 0x2.chr + time2bcd(Time.local(2021, 03, 06)).pack("C7")
      i2c.write bytes.b
      i2c.write 0x2.chr
      buf = i2c.read 7
      assert_equal Time.local(2021, 03, 06), bcd2time(buf.bytes)
    end
  end

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
      time.month - 1,
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
end
