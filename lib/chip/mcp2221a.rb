require 'myhidapi'

module Chip
  class MCP2221A
    extend Enumerable

    class Error < StandardError; end
    class CommandNotSupported < Error; end
    class Busy < Error; end
    class EmptyResponse < Error; end

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
      buf = pad [0xB0, section].pack('C*')
      write_request buf
      check_response read_response, 0xB0
    end

    def write_flash section, bytes
      buf = pad ([0xB1, section] + bytes).pack('C*')
      write_request buf
      check_response read_response, 0xB1
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

    def gp_settings= settings
      write_flash FlashData::GP_SETTINGS, settings.bytes
    end

    class GPSettings
      attr_reader :bytes

      def initialize bytes
        @bytes = bytes
      end

      def inspect
        to_s.sub(/>$/, " #{decode(@bytes).inspect}>")
      end

      def output_value_at i
        (bytes[i] >> 4) & 0x1
      end

      def set_output_value_at i, v
        bytes[i] &= ~(1 << 4)
        bytes[i] |= (1 & v) << 4
      end

      def direction_at i
        (bytes[i] >> 3) & 0x1
      end

      def set_direction_at v
        bytes[i] &= ~(1 << 3)
        bytes[i] |= (1 & v) << 3
      end

      def designation_at i
        (bytes[i] >> 0) & 0x3
      end

      def set_designation_at i
        bytes[i] &= ~(0x3 << 0)
        bytes[i] |= (0x3 & v) << 0
      end

      4.times { |i|
        [:output_value, :direction, :designation].each { |n|
          define_method("gp#{i}_#{n}") { send("#{n}_at", i) }
          define_method("gp#{i}_#{n}=") { |v| send("set_#{n}_at", i, v) }
        }
      }

      def decode bytes
        4.times.each_with_object({}) { |i, o|
          o[:"gp#{i}_output_value"] = output_value_at(i)
          o[:"gp#{i}_direction"]    = direction_at(i)
          o[:"gp#{i}_designation"]  = designation_at(i)
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

    def reset
      buf = pad ([0x70, 0xAB, 0xCD, 0xEF]).pack('C*')
      write_request buf
    end

    def i2c_write address, bytes
      send_i2c_command 0x90, address, bytes.bytesize, bytes
    end

    def i2c_write_no_stop address, bytes
      send_i2c_command 0x94, address, bytes.bytesize, bytes
    end

    def i2c_read_start address, length
      send_i2c_command 0x91, address, length, "".b
    end

    def i2c_read_repeated_start address, length
      send_i2c_command 0x93, address, length, "".b
    end

    def i2c_read
      buf = pad 0x40.chr
      write_request buf
      buf = check_response read_response, 0x40
      len = buf[3].ord
      buf[4, len]
    end

    def i2c_cancel
      buf = pad [0x10, 0x0, 0x10].pack('C*')
      write_request buf
      check_response read_response, 0x10
    end

    class I2CProxy
      def initialize address, handler
        @read_address  = (address << 1) | 1
        @write_address = address << 1
        @handler       = handler
      end

      def cancel; @handler.i2c_cancel; end

      def write buf
        @handler.i2c_write @write_address, buf
      end

      def read size
        @handler.i2c_read_start @read_address, 8
        @handler.i2c_read
      end
    end

    def i2c_on address
      I2CProxy.new address, self
    end

    private

    def send_i2c_command cmd, address, length, bytes
      buf = pad [cmd, length & 0xFF, (length >> 16) & 0xFF, address].pack('C*') + bytes
      write_request buf
      check_response read_response, cmd
    end

    def pad buf
      buf << ("\x0".b * (64 - buf.bytesize))
    end

    def check_response buf, type
      raise Error, buf unless buf[0].ord == type
      raise Busy, buf unless buf[1].ord == 0
      buf
    end

    def read_response
      # 300 ms timeout
      #return @handle.read 64
      @handle.read_timeout(64, 30) || raise(EmptyResponse)
    end

    def write_request buf
      retries = 0
      loop do
        break if handle.write buf
        retries += 1
        raise "Too many retries" if retries > 3
      end
    end

    attr_reader :handle
  end
end

chip = Chip::MCP2221A.first
i2c  = chip.i2c_on 0x51
i2c.cancel

loop do
  i2c.write 0x2.chr
  p i2c.read 8
  sleep 1
rescue Chip::MCP2221A::EmptyResponse
  puts "oh no"
  i2c.cancel
  retry
end