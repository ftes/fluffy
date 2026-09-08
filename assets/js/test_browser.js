import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

document.documentElement.dataset.fluffyTestBrowser = "ready"

const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
const liveRoot = document.querySelector("[data-phx-main]")

if (csrfToken && liveRoot) {
  const liveSocket = new LiveSocket("/live", Socket, {
    params: {_csrf_token: csrfToken}
  })

  liveSocket.connect()
  window.liveSocket = liveSocket
}
