require "uchip/mcp2221"

class OPT4048
  def self.find chip
    new chip.i2c_on(0x44)
  end

  class Settings < Struct.new(:fault_count, :int_pol, :latch, :operating_mode, :conversion_time, :range, :qwake)
    def self.from_int int
      fault_count = int & 0x3
      int_pol = (int >> 2) & 0x1
      latch = (int >> 3) & 0x1
      operating_mode = (int >> 4) & 0x3
      conversion_time = (int >> 6) & 0xF
      range = (int >> 10) & 0xF
      zero = (int >> 14) & 0x1
      raise unless zero == 0
      qwake = (int >> 15) & 0x1
      new(fault_count, int_pol, latch, operating_mode, conversion_time, range, qwake)
    end

    def to_int
      fault_count |
        (int_pol << 2) |
        (latch << 3) |
        (operating_mode << 4) |
        (conversion_time << 6) |
        (range << 10) |
        (qwake << 15)
    end

    def auto_range?
      range == Ranges::R_AUTOLUX
    end

    def conversion_time_ms
      ConversionTimes::MS_LUT[conversion_time]
    end

    module OperatingModes
      POWER_DOWN               = 0
      FORCED_AUTORANGE_ONESHOT = 1
      ONESHOT                  = 2
      CONTINUOUS               = 3
    end

    module ConversionTimes
      T_600US  = 0
      T_1MS    = 1
      T_1_8MS  = 2 # 1.8 ms
      T_3_4MS  = 3 # 3.4 ms
      T_6_5MS  = 4 # 6.5 ms
      T_12_7MS = 5 # 12.7 ms
      T_25MS   = 6
      T_50MS   = 7
      T_100MS  = 8
      T_200MS  = 9
      T_400MS  = 10
      T_800MS  = 11

      MS_LUT = [ 0.6, 1, 1.8, 3.4, 6.5, 12.7, 25, 50, 100, 200, 400, 800 ].freeze
    end

    module Ranges
      R_2KLUX2   = 0x0 # 2254 lux
      R_4KLUX5   = 0x1 # 4509 lux
      R_9LUX     = 0x2 # 9018 lux
      R_18LUX    = 0x3 # 18036 lux
      R_36LUX    = 0x4 # 36071 lux
      R_72LUX    = 0x5 # 72142 lux
      R_144LUX   = 0x6 # 144284 lux
      R_AUTOLUX  = 0xC # Auto
    end
  end

  module Registers
    SETTINGS = 0x0A
    DEVICE_ID = 0x11
  end

  def initialize i2c
    @i2c = i2c
  end

  def device_id
    @i2c.write Registers::DEVICE_ID.chr
    x = @i2c.read(2).unpack1("n")
    # DIDH is in the lower 12 bits
    ((x & 0xFFF) << 2) |
      # DIDL is in the upper 2 bits
      (x >> 2) & 0x3
  end

  def settings
    @i2c.write Registers::SETTINGS.chr
    Settings.from_int @i2c.read(2).unpack1("n")
  end

  def settings= settings
    @i2c.write [Registers::SETTINGS, settings.to_int].pack("Cn")
  end

  # red
  def ch0; read_ch 0; end

  # green
  def ch1; read_ch 0x2; end

  # blue
  def ch2; read_ch 0x4; end

  # white
  def ch3; read_ch 0x6; end

  class AllValues
    include Enumerable

    def initialize vals
      @vals = vals
    end

    def each(&blk); @vals.each(&blk); end

    def red; @vals[0]; end
    def green; @vals[1]; end
    def blue; @vals[2]; end
    def white; @vals[3]; end

    def CIEx
      x, y, z = cie(red, green, blue)
      x / (x + y + z)
    end

    def CIEy
      x, y, z = cie(red, green, blue)
      y / (x + y + z)
    end

    def lux
      green.value * 0.00215
    end

    def CCT
      cie_x = self.CIEx
      cie_y = self.CIEy

      n = (cie_x - 0.3320) / (0.1858 - cie_y)
      (437 * (n ** 3)) + (3601 * (n ** 2)) + (6861 * n) + 5517
    end

    private

    def cie r, g, b
      x = r.value * CIE_LUT[0][0]
      x += g.value * CIE_LUT[1][0]
      x += b.value * CIE_LUT[2][0]

      y = r.value * CIE_LUT[0][1]
      y += g.value * CIE_LUT[1][1]
      y += b.value * CIE_LUT[2][1]

      z = r.value * CIE_LUT[0][2]
      z += g.value * CIE_LUT[1][2]
      z += b.value * CIE_LUT[2][2]

      [x, y, z]
    end
  end

  def read_all
    @i2c.write 0.chr
    AllValues.new @i2c.read(4 * 4).unpack("NNNN").map { |x| CH.from_int x }
  end

  def lux
    ch1.value * 0.00215
  end

  # From TI datasheet: 9.2.4 Application Curves
  CIE_LUT = [
    [0.000234892992, -0.0000189652390, 0.0000120811684, 0],
    [0.0000407467441, 0.000198958202, -0.0000158848115, 0.00215],
    [0.0000928619404, -0.0000169739553, 0.000674021520, 0],
    [0, 0, 0, 0]
  ]

  def CIEx
    read_all.CIEx
  end

  def CIEy
    read_all.CIEy
  end

  def CCT
    read_all.CCT
  end

  class CH < Struct.new(:counter, :crc, :value)
    def self.from_int value
      msb = (value >> 16) & 0xFFF
      exp = (value >> 28) & 0xF
      crc = value & 0xF
      counter = (value >> 4) & 0xF
      lsb = (value >> 8) & 0xFF
      new(counter, crc, (msb << 8) | lsb)
    end
  end

  private

  def read_ch x
    @i2c.write x.chr
    CH.from_int @i2c.read(4).unpack1("N")
  end
end

chip = UChip::MCP2221.first || raise("Couldn't find mcp2221")
if chip.status.getbyte(8) != 0
  puts "reset chip, try again"
  chip.reset
  exit!
end

dev = OPT4048.find chip
raise("wrong device") unless dev.device_id == 0x2084

s = dev.settings
s.operating_mode = 3  # continuous
s.conversion_time = 9 # 200ms

dev.settings = s

p dev.settings

loop do
  sleep 1
  all = dev.read_all
  p [all.CCT, all.lux]
end
