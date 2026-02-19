module Config
  def self.get(key)
    @config ||= get_config
    @config[key]
  end

  def self.get_config
    env = ENV.fetch('APP_ENV', 'development')
    config_path = File.expand_path("config/#{env}.rb", __dir__)

    unless File.exist?(config_path)
      raise "Configuration file not found for environment: #{env}"
    end

    eval(File.read(config_path))
  end

  def self.campsite_url
    get(:campsite_url)
  end

  def self.login_url
    get(:login_url) || "https://www.nap-camp.com/identity/sessions/new"
  end

  def self.book_url
    get(:book_url)
  end

  def self.email
    get(:email)
  end

  def self.password
    get(:password)
  end

  def self.target_plan_name
    get(:target_plan_name)
  end

  def self.check_in_date
    get(:check_in_date)
  end

  def self.check_out_date
    get(:check_out_date)
  end

  def self.headless
    raw = get(:headless)
    return true if raw.nil?
    raw == true || raw == 1
  end

  def self.timeout
    Integer(get(:timeout) || 30)
  end

  def self.smtp_host
    get(:smtp_host)
  end

  def self.smtp_rehearsal
    smtp_host.nil?
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
    get(:smtp_from) || smtp_user
  end

  def self.smtp_to
    get(:smtp_to)
  end
end
