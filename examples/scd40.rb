require "uchip/mcp2221"

class SCD40
  def self.find chip
    i2c = chip.i2c_on 0x62
    new i2c
  end

  CRC8_INIT = 0xFF
  CRC8_POLYNOMIAL = 0x31

  def self.crc a, b
    crc_byte(crc_byte(CRC8_INIT, a), b)
  end

  def self.crc_byte crc, a
    crc = crc ^ a
    8.times do
      if crc & 0x80 != 0
        crc = ((crc << 1) ^ CRC8_POLYNOMIAL) & 0xFF
      else
        crc = (crc << 1) & 0xFF
      end
    end
    crc
  end

  attr_reader :i2c

  def initialize i2c
    @i2c = i2c
  end

  def get_serial_number
    cmd = [0x3682]
    i2c.write(cmd.pack("n"))
    sleep 0.001
    list = i2c.read(9).unpack("nCnCnC")
    list.each_slice(2).inject(0) do |m, (x, y)|
      raise unless y == crc16(x)
      (m << 8) | x
    end
  end

  def start_periodic_measurement
    cmd = [0x21b1]
    i2c.write(cmd.pack("n"))
    sleep 0.001
  end

  def stop_periodic_measurement
    cmd = [0x3f86]
    i2c.write(cmd.pack("n"))
    sleep 0.001
  end

  def read_measurement
    cmd = [0xec05]
    i2c.write(cmd.pack("n"))
    sleep 0.001
    list = i2c.read(9).unpack("nCnCnC")
    co2, t, rh = list.each_slice(2).map do |x, y|
      raise unless y == crc16(x)
      x
    end
    t = -45 + (175 * t >> 16)
    rh = (100 * rh) >> 16
    [co2, t, rh]
  end

  def get_data_ready_status
    cmd = [0xe4b8]
    i2c.write(cmd.pack("n"))
    sleep 0.001
    res, crc = i2c.read(3).unpack("nC")
    raise unless crc == crc16(res)
    res
  end

  def ready?; get_data_ready_status != 0x8000; end

  def crc16 byte
    crc(byte >> 8, byte & 0xFF)
  end

  def crc a, b
    self.class.crc a, b
  end
end

# Find the first connected chip
chip = UChip::MCP2221.first || raise("Couldn't find the chip!")
scd40 = SCD40.find chip
num = scd40.get_serial_number
p num
scd40.start_periodic_measurement
begin
  loop do
    if scd40.ready?
      p scd40.read_measurement => Time.now
    end
  end
ensure
  p :stopping
  scd40.stop_periodic_measurement
end
