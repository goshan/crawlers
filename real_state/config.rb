module Config
  LOCATION_CONFIG = {
    all: { label: "全体", color: "#D62728" },
    koto: { label: "江東区", color: "#1F77B4" },
    kamedo: { label: "亀戸", color: "#6BAED6" },
    shinagawa: { label: "品川区", color: "#9467BD" },
    minamioi: { label: "南大井", color: "#C5B0D5" },
    meguro: { label: "目黒区", color: "#2CA02C" },
    honcho: { label: "目黒本町", color: "#74C476" }
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
    
    config_data = eval(File.read(config_path))

    if env == 'production'
      config_data
    else
      config_data
    end
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

  def self.redis_url
    get(:redis_url) || "redis://127.0.0.1:6379/0"
  end

  def self.smtp_host
    get(:smtp_host)
  end

  def self.smtp_rehearsal
    self.smtp_host.nil?
  end

  def self.smtp_port
    get(:smtp_port)
  end

  def self.smtp_user
    get(:smtp_user)
  end

  def self.smtp_pass
    get(:smtp_pass)
  end

  def self.smtp_from
    get(:smtp_from) || self.smtp_user
  end

  def self.smtp_to
    get(:smtp_to)
  end
end

