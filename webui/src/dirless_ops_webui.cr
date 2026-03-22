require "lucky"
require "lucky_env"

LuckyEnv.load?(".env")

require "./app_server"
require "../config/**"
require "./dirless/ops/webui/responses"
require "./dirless/ops/webui/daemon_client"
require "./dirless/ops/webui/auth"
require "./pages/main_layout"
require "./pages/**"
require "./actions/browser_action"
require "./actions/**"

Habitat.raise_if_missing_settings!

AppServer.new.listen
