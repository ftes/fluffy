import "/vendor/phoenix_html/phoenix_html.js"
import {Socket} from "/vendor/phoenix/phoenix.mjs"
import {LiveSocket} from "/vendor/phoenix_live_view/phoenix_live_view.esm.js"

document.documentElement.dataset.fluffyTestBrowser = "ready"

const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
const liveRoot = document.querySelector("[data-phx-main], [data-phx-session]")

if (csrfToken && liveRoot) {
  const liveSocket = new LiveSocket("/live", Socket, {
    params: {_csrf_token: csrfToken}
  })

  liveSocket.connect()
  window.liveSocket = liveSocket
}
