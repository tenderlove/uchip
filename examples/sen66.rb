require "uchip/mcp2221"

##
# Client for SEN66
#   https://sensirion.com/media/documents/FAFC548D/68C12881/Sensirion_Datasheet_SEN6x.pdf
class SEN66
  CRC8_POLYNOMIAL = 0x31
  CRC8_INIT = 0xFF

  def self.find chip
    new chip.i2c_on(0x6B)
  end

  def initialize i2c
    @i2c = i2c
  end

  def product_name
    @i2c.write [0xD0, 0x14].pack("CC")
    read_fields(16).pack("n16").unpack1("Z*")
  end

  def serial_number
    @i2c.write [0xD0, 0x33].pack("CC")
    read_fields(16).pack("n16").unpack1("Z*")
  end

  def start
    @i2c.write [0x00, 0x21].pack("CC")
  end

  def stop
    @i2c.write [0x01, 0x04].pack("CC")
  end

  def data_ready?
    @i2c.write [0x02, 0x02].pack("CC")
    read_fields(1).first == 1
  end

  Reading = Struct.new(:pm_1_0, :pm_2_5, :pm_4_0, :pm_10_0,
    :rh, :temp, :voc, :nox, :co2)

  def read
    @i2c.write [0x03, 0x00].pack("CC")
    pm1, pm25, pm4, pm10, rh, temp, voc, nox, co2 = *read_fields(9)
    Reading.new(pm1 / 10.0, pm25 / 10.0, pm4 / 10.0, pm10 / 10.0,
      rh / 100.0, temp / 200.0, voc / 10.0, nox / 10.0, co2)
  end

  private

  def read_fields count
    @i2c.read(count * 3).unpack("nC" * count).each_slice(2).map { |x, crc|
      raise "crc failure" unless crc16(x) == crc
      x
    }
  end

  def crc8 crc, byte
    crc ^= byte
    8.times do
      if (crc & 0x80) == 0x80
        crc = ((crc << 1) ^ CRC8_POLYNOMIAL) & 0xFF
      else
        crc = (crc << 1) & 0xFF
      end
    end
    crc
  end

  def crc16 num
    crc8(crc8(CRC8_INIT, num >> 8), num & 0xFF)
  end
end

chip = UChip::MCP2221.first || raise("Couldn't find mcp2221")
if chip.status.getbyte(8) != 0
  puts "reset chip, try again"
  chip.reset
  exit!
end

sen66 = SEN66.find chip
begin
  p sen66.product_name
  p sen66.serial_number
  sen66.start
  sleep 0.1 # 100ms warmup

  loop do
    sleep 0.4
    if sen66.data_ready?
      p sen66.read
    end
  end

ensure
  sen66.stop
end
