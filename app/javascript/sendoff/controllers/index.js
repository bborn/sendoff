import { application } from "sendoff/controllers/application"

import ClipboardController from "sendoff/controllers/clipboard_controller"
import ToastsController from "sendoff/controllers/toasts_controller"

application.register("clipboard", ClipboardController)
application.register("toasts", ToastsController)

// Screen slices register their controllers here (kanban, modal, panel,
// sending-countdown, cmdk) as they are added.
