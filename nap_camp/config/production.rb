{
  campsite_url: "https://www.nap-camp.com/kanagawa/14007",
  book_url: "https://www.nap-camp.com/reservations/step1?campsite_id=14007",
  email: ENV["NAP_CAMP_EMAIL"],
  password: ENV["NAP_CAMP_PASSWORD"],
  target_plan_name: ENV.fetch("NAP_CAMP_PLAN"),
  check_in_date: ENV.fetch("NAP_CAMP_CHECK_IN"),
  check_out_date: ENV.fetch("NAP_CAMP_CHECK_OUT"),
  headless: true,
  timeout: 60,
  smtp_host: "smtp.gmail.com",
  smtp_port: 587,
  smtp_user: ENV["SMTP_USER"],
  smtp_pass: ENV["SMTP_PASS"],
  smtp_to: ENV["SMTP_TO"]
}
