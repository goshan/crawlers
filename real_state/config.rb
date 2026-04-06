module Config
  LOCATION_CONFIG = {
    all:       "全体",
    koto:      "江東区",
    kamedo:    "亀戸",
    shinagawa: "品川区",
    minamioi:  "南大井",
    meguro:    "目黒区",
    honcho:    "目黒本町"
  }.freeze

  def self.get(key)
    @config ||= get_config
    @config[key]
  end

  def self.get_config
    env = ENV.fetch('APP_ENV', 'development')
    config_path = File.expand_path("../config/#{env}.rb", __FILE__)
    
    unless File.exist?(config_path)
      raise "Configuration file not found for environment: #{env}"
    end
    
    eval(File.read(config_path))
  end

  def self.start_url
    url = get(:start_url)
    url = url.strip if url.respond_to?(:strip)
    url = nil if url && url.empty?
    raise "Start URL is required." unless url
    url
  end

  def self.max_page
    count = Integer(get(:max_page))
    count <= 0 ? nil : count
  rescue ArgumentError, TypeError
    nil
  end

  def self.sampling_rate
    default = 1.0
    raw = get(:sampling_rate)
    return default if raw.nil?
    Float(raw)
  rescue ArgumentError, TypeError
    default
  end

  def self.quiet_mode
    raw = get(:quiet_mode)
    return false if raw.nil?
    raw == true || raw == 1
  end

  def self.sleep_seconds
    default = 0.0
    raw = get(:sleep_seconds)
    return default if raw.nil?
    seconds = Float(raw)
    seconds.negative? ? default : seconds
  rescue ArgumentError, TypeError
    default
  end

  def self.requests_per_sleep
    default = 0
    raw = get(:requests_per_sleep)
    return default if raw.nil?
    count = Integer(raw)
    count < 0 ? default : count
  rescue ArgumentError, TypeError
    default
  end

  def self.max_retry
    default = 1
    raw = get(:max_retry)
    return default if raw.nil?
    count = Integer(raw)
    count <= 0 ? default : count
  rescue ArgumentError, TypeError
    default
  end

  def self.mysql
    {
      host:     get(:mysql_host)     || "127.0.0.1",
      port:     get(:mysql_port)     || 3306,
      database: get(:mysql_database) || "real_state",
      username: get(:mysql_username) || "root",
      password: get(:mysql_password) || "",
      encoding: "utf8mb4"
    }
  end

  def self.slack_webhook_url
    get(:slack_webhook_url)
  end

  def self.slack_rehearsal
    self.slack_webhook_url.nil?
  end
end

