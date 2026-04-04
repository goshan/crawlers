{
  start_url: "https://suumo.jp/jj/bukken/ichiran/JJ012FC001/?ar=030&bs=011&ta=13&sc=13108&sc=13109&sc=13110&cn=9999999&cnb=0&et=9999999&hb=0&ht=9999999&kb=1&kj=9&km=1&kt=9999999&mb=0&mt=9999999&ni=9999999&pc=100&pj=1&po=0&tb=0&tj=0&tt=9999999",
  quiet_mode: 1,
  sleep_seconds: 10.0,
  requests_per_sleep: 10,
  max_retry: 5,
  db_path: ENV.fetch("DB_PATH", File.expand_path("../../metrics.db", __FILE__)),
  slack_webhook_url: ENV["SLACK_WEBHOOK_URL"]
}
