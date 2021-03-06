require 'pathname'
require 'rb-inotify' if linux?
require 'singleton'
require 'yaml'

libdir = File.dirname(__FILE__)
require File.join(libdir, 'log')
require File.join(libdir, 'callback')

module TransmissionRSS
  # Class handles configuration parameters.
  class Config < Hash
    # This is a singleton class.
    include Singleton

    extend Callback
    callback(:on_change) # Declare callback for changed config.

    def initialize(file = nil)
      self.merge_defaults!
      self.load(file) unless file.nil?

      @log = Log.instance
    end

    # Merges a Hash or YAML file (containing a Hash) with itself.
    def load(config)
      case config.class.to_s
      when 'Hash'
        self.merge!(config)
      when 'String'
        self.merge_yaml!(config)
      else
        raise ArgumentError.new('Could not load config.')
      end
    end

    def merge_defaults!
      self.merge!({
        'feeds' => [],
        'update_interval' => 600,
        'add_paused' => false,
        'server' => {
          'host' => 'localhost',
          'port' => 9091,
          'rpc_path' => '/transmission/rpc'
        },
        'login' => nil,
        'log_target' => $stderr,
        'fork' => false,
        'pid_file' => false,
        'privileges' => {},
        'seen_file' => nil
      })
    end

    # Merge Config Hash with Hash from YAML file.
    def merge_yaml!(path, watch = true)
      self.merge!(YAML.load_file(path))
    rescue TypeError
      # If YAML loading fails, .load_file returns `false`.
    else
      watch_file(path) if watch && linux?
    end

    def reset!
      self.clear
      self.merge_defaults!
    end

    def watch_file(path)
      path = Pathname.new(path).realpath.to_s
      @log.debug('watch_file ' + path)

      @notifier ||= INotify::Notifier.new
      @notifier.watch(path, :close_write) do |e|
        self.reset!
        self.merge_yaml!(path, false)

        @log.debug('reloaded config file ' + path)
        @log.debug(self)

        on_change
      end

      @notifier_thread ||= Thread.start do
        @notifier.run
      end
    end
  end
end
