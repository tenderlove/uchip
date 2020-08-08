require 'myhidapi'

module Chip
  class MCP2221A
    extend Enumerable

    class Error < StandardError; end
    class CommandNotSupported < Error; end

    def self.each
      MyHIDAPI.enumerate(0x04d8, 0x00dd).each { |dev| yield new dev }
    end

    def initialize dev
      @dev = dev
      @handle = dev.open
    end

    def usb_manufacturer
      handle.manufacturer
    end

    def usb_product
      handle.product
    end

    def read_flash section
      retries = 0
      buf = [0xB0, section].pack('C*')
      buf << ("\x0".b * (64 - buf.bytesize))

      loop do
        break if handle.write buf
        retries += 1
        raise "Too many retries" if retries > 3
      end

      buf = @handle.read_timeout 64, 300 # 300 ms timeout
      raise "Nothing read!" unless buf
      raise CommandNotSupported, buf unless buf.start_with?("\xB0\x0".b)
      buf
    end

    def write_flash section, bytes
      retries = 0
      buf = ([0xB1, section] + bytes).pack('C*')
      buf << ("\x0".b * (64 - buf.bytesize))

      loop do
        break if handle.write buf
        retries += 1
        raise "Too many retries" if retries > 3
      end

      buf = @handle.read_timeout 64, 300 # 300 ms timeout
      raise CommandNotSupported, buf unless buf.start_with?("\xB1\x0".b)
      true
    end

    class ChipSettings
      def initialize bytes
        @bytes = bytes
      end

      def inspect
        to_s.sub(/>$/, " #{decode(@bytes).inspect}>")
      end

      BIT_FIELDS = []
      def self.bool_attr_accessor name, index, offset
        BIT_FIELDS << name
        define_method(name) do
          !((bytes[index] >> offset) & 0x1).zero?
        end

        define_method(:"#{name}=") do |v|
          v ?  bytes[index] |= (1 << offset) : bytes[index] &= ~(1 << offset)
        end
      end

      def self.bit_attr_accesor name, index, offset, mask
        BIT_FIELDS << name
        define_method(name) do
          (bytes[index] >> offset) & mask
        end

        define_method(:"#{name}=") do |v|
          bytes[index] &= ~(mask << offset)
          bytes[index] |= ((mask & v) << offset)
        end
      end

      #                                             bytes[i], shift, mask
      bool_attr_accessor :cdc,                             0,     7
      bool_attr_accessor :led_uart_rx,                     0,     6
      bool_attr_accessor :led_uart_tx,                     0,     5
      bool_attr_accessor :led_i2c,                         0,     4
      bool_attr_accessor :sspnd,                           0,     3
      bool_attr_accessor :usbcfg,                          0,     2
      bit_attr_accesor   :security,                        0,     0, 0x3
      bit_attr_accesor   :clock_output_divider,            1,     0, 0x1F
      bit_attr_accesor   :dac_reference_voltage,           2,     6, 0x3
      bool_attr_accessor :dac_reference_option,            2,     5
      bit_attr_accesor   :dac_power_up_value,              2,     0, 0x1F
      bool_attr_accessor :interrupt_detection_negative,    3,     6
      bool_attr_accessor :interrupt_detection_positive,    3,     5
      bit_attr_accesor   :adc_reference_voltage,           3,     3, 0x3
      bool_attr_accessor :dac_voltage,                     3,     2

      def decode bytes
        BIT_FIELDS.each_with_object({}) { |n, o| o[n] = send n }.merge({
          :vid                          => bytes[4] + (bytes[5] << 8),
          :pid                          => bytes[6] + (bytes[7] << 8),
          :usb_power_attributes         => bytes[8],
          :usb_requested_mas            => bytes[9],
        })
      end

      attr_reader :bytes
    end

    module FlashData
      CHIP_SETTINGS         = 0x00
      GP_SETTINGS           = 0x01
      MANUFACTURER          = 0x02
      PRODUCT               = 0x03
      SERIAL_NUMBER         = 0x04
      FACTORY_SERIAL_NUMBER = 0x05
    end

    def chip_settings
      buf = read_flash(FlashData::CHIP_SETTINGS).bytes
        .drop(2) # response header
        .drop(2) # not care (according to data sheet)
        .first(10)
      ChipSettings.new buf
    end

    def chip_settings= settings
      write_flash FlashData::CHIP_SETTINGS, settings.bytes
    end

    class GPSettings
      def initialize bytes
        @bytes = bytes
      end

      def inspect
        to_s.sub(/>$/, " #{decode(@bytes).inspect}>")
      end

      def decode bytes
        4.times.each_with_object({}) { |i, o|
          o[:"gp#{i}_output_value"] = (bytes[i] >> 4) & 0x1
          o[:"gp#{i}_direction"]    = (bytes[i] >> 3) & 0x1
          o[:"gp#{i}_designation"]  = (bytes[i] >> 0) & 0x3
        }
      end
    end

    def gp_settings
      buf = read_flash(FlashData::GP_SETTINGS).bytes
        .drop(2) # response header
        .drop(2) # structure length, don't care
        .first(4)
      GPSettings.new buf
    end

    def manufacturer
      byte_count, _, *rest = read_flash(FlashData::MANUFACTURER).bytes
        .drop(2) # response header
      rest[0, byte_count - 2].pack('U*')
    end

    def product
      byte_count, _, *rest = read_flash(FlashData::PRODUCT).bytes
        .drop(2) # response header
      rest[0, byte_count - 2].pack('U*')
    end

    def serial_number
      byte_count, _, *rest = read_flash(FlashData::SERIAL_NUMBER).bytes
        .drop(2) # response header
      rest[0, byte_count - 2].pack('U*')
    end

    def factory_serial_number
      byte_count, _, *rest = read_flash(FlashData::FACTORY_SERIAL_NUMBER).bytes
        .drop(2) # response header
      rest[0, byte_count - 2].pack('U*')
    end

    private

    attr_reader :handle
  end
end

chip = Chip::MCP2221A.first
settings = chip.chip_settings
p settings
p settings.cdc
settings.cdc = false
chip.chip_settings = settings
p chip.chip_settings.cdc
