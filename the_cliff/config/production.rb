{
  house_url:      "https://thecliff.airhost.co/en/houses/358897",
  check_in_date:  ENV.fetch("CLIFF_CHECK_IN"),
  check_out_date: ENV.fetch("CLIFF_CHECK_OUT"),
  num_rooms:      ENV.fetch("CLIFF_NUM_ROOMS", "1"),
  headless:       true,
  timeout: 60,
  smtp_host:      "smtp.gmail.com",
  smtp_port:      587,
  smtp_user:      ENV["SMTP_USER"],
  smtp_pass:      ENV["SMTP_PASS"],
  smtp_to:        ENV["SMTP_TO"]
}
